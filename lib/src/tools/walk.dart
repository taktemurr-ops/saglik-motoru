/// Yürüyüş rotaları ve kayıt: GPS ile yürüyüş kaydı (yalnızca ekran
/// açıkken), mesafe, süre, tempo, tırmanış/iniş, tahmini adım; kaydı adlı
/// rota olarak saklama, yükseklik profili, GPX paylaşma ve kayıtlı rotayı
/// yeniden yürürken rotaya uzaklık / kalan mesafe. Harita karosu yok,
/// tamamen çevrimdışı.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../logic.dart';
import 'activity.dart' show RoutePainter;

typedef _Js = Map<String, Object?>;

Future<bool> _locationOk(BuildContext context, ToolContext t) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      if (!context.mounted) return false;
      if (!await rationaleOnce(context, t, 'location', Icons.location_on_rounded)) return false;
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}

List<(double, double)> _pts(_Js r) => [
      for (final p in (r['pts'] as List?) ?? const [])
        if (p is List && p.length >= 2) ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];

List<double> _alts(_Js r) => [
      for (final p in (r['pts'] as List?) ?? const [])
        if (p is List && p.length >= 3) (p[2] as num).toDouble(),
    ];

/// İki rotayı üst üste çizer: kayıtlı rota (soluk) ve canlı iz.
class _FollowPainter extends CustomPainter {
  final List<(double, double)> route;
  final List<(double, double)> live;
  final Color color;
  _FollowPainter(this.route, this.live, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...route, ...live];
    if (all.length < 2) return;
    final xy = projectRoute(all, size.width - 16, size.height - 16);
    Path path(int from, int to) {
      final p = Path()..moveTo(xy[from].$1 + 8, xy[from].$2 + 8);
      for (var i = from + 1; i < to; i++) {
        p.lineTo(xy[i].$1 + 8, xy[i].$2 + 8);
      }
      return p;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (route.length >= 2) {
      canvas.drawPath(path(0, route.length), stroke
        ..color = Colors.white38
        ..strokeWidth = 6);
    }
    if (live.length >= 2) {
      canvas.drawPath(path(route.length, all.length), stroke
        ..color = color
        ..strokeWidth = 3);
    }
    if (live.isNotEmpty) {
      final me = xy.last;
      canvas.drawCircle(Offset(me.$1 + 8, me.$2 + 8), 7, Paint()..color = Colors.lightBlueAccent);
      canvas.drawCircle(Offset(me.$1 + 8, me.$2 + 8), 7, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_FollowPainter old) => true;
}

class WalkTool extends StatefulWidget {
  final ToolContext t;
  const WalkTool(this.t, {super.key});

  @override
  State<WalkTool> createState() => _WalkToolState();
}

class _WalkToolState extends State<WalkTool> {
  List<_Js> _routes = [];
  bool _loaded = false;
  bool? _ok;
  double _stride = 0.75;

  // Kayıt
  bool _recording = false, _paused = false;
  final List<(double, double, double, int)> _trk = [];
  double _dist = 0;
  int _movingMs = 0, _lastMs = 0;
  StreamSubscription<Position>? _sub;
  Timer? _tick;

  // İzlenen rota (yeniden yürüme).
  _Js? _follow;
  _Js? _detail;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await t.store.readList('routes');
    final st = await t.store.readDouble('stride', 0.75);
    if (!mounted) return;
    setState(() {
      _routes = r;
      _stride = st;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_sub?.cancel());
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _start({_Js? follow}) async {
    final ok = await _locationOk(context, t);
    if (!mounted) return;
    setState(() => _ok = ok);
    if (!ok) return;
    setState(() {
      _follow = follow;
      _detail = null;
      _recording = true;
      _paused = false;
      _trk.clear();
      _dist = 0;
      _movingMs = 0;
      _lastMs = DateTime.now().millisecondsSinceEpoch;
    });
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!_paused) _movingMs += now - _lastMs;
      _lastMs = now;
      if (mounted) setState(() {});
    });
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3),
    ).listen((p) {
      if (!mounted || _paused || p.accuracy > 30) return;
      setState(() {
        if (_trk.isNotEmpty) {
          final d = haversine(_trk.last.$1, _trk.last.$2, p.latitude, p.longitude);
          if (d >= 2 && d < 200) _dist += d;
        }
        _trk.add((p.latitude, p.longitude, p.altitude, DateTime.now().millisecondsSinceEpoch));
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _ok = false);
    });
  }

  Future<void> _finish() async {
    _tick?.cancel();
    await _sub?.cancel();
    _sub = null;
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    if (_dist >= 30 && _trk.length >= 2 && mounted) {
      final name = await _askName(_follow == null ? '' : '${_follow!['name']}');
      final step = math.max<int>(1, _trk.length ~/ 600);
      final r = <String, Object?>{
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': (name == null || name.isEmpty) ? MaterialLocalizations.of(context).formatMediumDate(DateTime.now()) : name,
        'at': DateTime.now().millisecondsSinceEpoch,
        'm': _dist.round(),
        's': _movingMs ~/ 1000,
        'pts': [
          for (var i = 0; i < _trk.length; i += step)
            [_trk[i].$1, _trk[i].$2, double.parse(_trk[i].$3.toStringAsFixed(1)), _trk[i].$4],
        ],
      };
      _routes = [r, ..._routes].take(200).toList();
      await t.store.writeList('routes', _routes);
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _follow = null;
      });
    }
  }

  Future<String?> _askName(String initial) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L(t, 'route_name')),
        content: TextField(controller: c, autofocus: true, onSubmitted: (s) => Navigator.pop(ctx, s)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L(t, 'skip'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(L(t, 'save'))),
        ],
      ),
    );
    c.dispose();
    return v?.trim();
  }

  Future<void> _shareGpx(_Js r) async {
    final gpx = toGpx('${r['name']}', [
      for (final p in (r['pts'] as List?) ?? const [])
        if (p is List && p.length >= 2)
          (
            (p[0] as num).toDouble(),
            (p[1] as num).toDouble(),
            p.length >= 3 ? (p[2] as num).toDouble() : null,
            p.length >= 4 ? (p[3] as num).toInt() : null,
          ),
    ]);
    final safe = '${r['name']}'.replaceAll(RegExp(r'[^\w\-]+'), '_');
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(utf8.encode(gpx)), mimeType: 'application/gpx+xml', name: '$safe.gpx')],
        fileNameOverrides: ['$safe.gpx'],
      ));
    } catch (_) {}
  }

  String _steps(double m) => '${(m / math.max(0.3, _stride)).round()}';

  Widget _recordingView() {
    final s = AppLook.of(context);
    final secs = _movingMs ~/ 1000;
    final alts = [for (final p in _trk) p.$3];
    final (gain, _) = elevationGainLoss(alts);
    final live = [for (final p in _trk) (p.$1, p.$2)];
    final route = _follow == null ? const <(double, double)>[] : _pts(_follow!);
    double? off, left;
    if (route.length >= 2 && live.isNotEmpty) {
      final (d, along) = routeProgress(route, live.last.$1, live.last.$2);
      off = d;
      left = math.max(0.0, routeLength(route) - along);
    }
    return ToolList(children: [
      if (_trk.isEmpty) AppInfoCard(L(t, 'waiting_gps'), icon: Icons.satellite_alt_rounded),
      BigReadout(fmt(_dist / 1000, 2), unit: 'km', caption: L(t, 'distance')),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'duration'), value: clock(secs, hours: true), lang: t.lang),
          AppResult(label: L(t, 'pace'), value: '${pace(secs, _dist)} /km', lang: t.lang),
          AppResult(label: L(t, 'climb'), value: '${gain.round()} m', lang: t.lang),
          AppResult(label: L(t, 'steps_est'), value: _steps(_dist), lang: t.lang),
          if (left != null) AppResult(label: L(t, 'remaining'), value: '${fmt(left / 1000, 2)} km', lang: t.lang),
          if (off != null)
            AppResult(
              label: L(t, 'off_route'),
              value: '${off.round()} m',
              lang: t.lang,
            ),
        ]),
      ),
      if (off != null && off > 40) WarnCard(L(t, 'off_route_warn'), icon: Icons.wrong_location_rounded),
      if (route.isNotEmpty || live.length >= 2)
        AppPanel(
          child: SizedBox(height: 240, child: CustomPaint(size: Size.infinite, painter: _FollowPainter(route, live, s.accent))),
        ),
      Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
        AppButton(
          label: L(t, _paused ? 'resume' : 'pause'),
          icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          onPressed: () => setState(() => _paused = !_paused),
        ),
        AppButton(label: L(t, 'finish'), icon: Icons.flag_rounded, onPressed: _finish),
      ]),
      AppInfoCard(L(t, 'fg_note'), icon: Icons.screen_lock_portrait_rounded),
    ]);
  }

  Widget _detailView(_Js r) {
    final s = AppLook.of(context);
    final pts = _pts(r);
    final alts = _alts(r);
    final (gain, loss) = elevationGainLoss(alts);
    final m = ((r['m'] as num?) ?? 0).toDouble();
    final secs = ((r['s'] as num?) ?? 0).toInt();
    return ToolList(children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() => _detail = null),
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(L(t, 'back')),
        ),
      ),
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${r['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(MaterialLocalizations.of(context).formatFullDate(DateTime.fromMillisecondsSinceEpoch(((r['at'] as num?) ?? 0).toInt())),
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          SizedBox(height: 220, child: CustomPaint(size: Size.infinite, painter: RoutePainter(pts, s.accent))),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'distance'), value: '${fmt(m / 1000, 2)} km', lang: t.lang),
          AppResult(label: L(t, 'duration'), value: clock(secs, hours: true), lang: t.lang),
          AppResult(label: L(t, 'pace'), value: '${pace(secs, m)} /km', lang: t.lang),
          AppResult(label: L(t, 'climb'), value: '${gain.round()} m', lang: t.lang),
          AppResult(label: L(t, 'descent'), value: '${loss.round()} m', lang: t.lang),
          AppResult(label: L(t, 'steps_est'), value: _steps(m), lang: t.lang),
        ]),
      ),
      if (alts.length >= 2) ...[
        AppHeading(L(t, 'elevation'), icon: Icons.terrain_rounded),
        Sparkline(alts),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          AppButton(label: L(t, 'walk_again'), icon: Icons.replay_rounded, onPressed: () => _start(follow: r)),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _shareGpx(r),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('GPX'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final n = await _askName('${r['name']}');
                  if (n == null || n.isEmpty) return;
                  setState(() => r['name'] = n);
                  await t.store.writeList('routes', _routes);
                },
                icon: const Icon(Icons.edit_rounded),
                label: Text(L(t, 'edit')),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: L(t, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (!await confirm(context, t, L(t, 'delete_q'))) return;
                setState(() {
                  _routes.removeWhere((x) => x['id'] == r['id']);
                  _detail = null;
                });
                await t.store.writeList('routes', _routes);
              },
            ),
          ]),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_recording) return _recordingView();
    final d = _detail;
    if (d != null) return _detailView(d);
    final s = AppLook.of(context);
    final total = _routes.fold<double>(0, (a, r) => a + ((r['m'] as num?) ?? 0).toDouble());
    final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final week = _routes
        .where((r) => ((r['at'] as num?) ?? 0) >= weekAgo)
        .fold<double>(0, (a, r) => a + ((r['m'] as num?) ?? 0).toDouble());
    return ToolList(children: [
      if (_ok == false) notAvailable(t),
      if (_ok == false) AppInfoCard(appTx('perm_denied', t.lang)),
      AppPanel(
        child: Column(children: [
          Icon(Icons.hiking_rounded, size: 64, color: s.accent),
          AppResult(label: L(t, 'this_week'), value: '${fmt(week / 1000, 1)} km', lang: t.lang),
          AppResult(label: L(t, 'total'), value: '${fmt(total / 1000, 1)} km', lang: t.lang),
          AppResult(label: L(t, 'routes'), value: '${_routes.length}', lang: t.lang),
          const SizedBox(height: 8),
          AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: () => _start()),
        ]),
      ),
      SliderRow(
        label: L(t, 'stride'),
        value: _stride,
        min: 0.4,
        max: 1.1,
        divisions: 14,
        text: (v) => '${fmt(v, 2)} m',
        onChanged: (v) {
          setState(() => _stride = v);
          t.store.write('stride', '$v');
        },
      ),
      if (_routes.isNotEmpty) AppHeading(L(t, 'routes'), icon: Icons.route_rounded),
      for (final r in _routes.take(60))
        AppPanel(
          padding: const EdgeInsets.all(6),
          child: InkWell(
            onTap: () => setState(() => _detail = r),
            child: Row(children: [
              SizedBox(width: 90, height: 70, child: CustomPaint(painter: RoutePainter(_pts(r), s.accent))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${fmt(((r['m'] as num?) ?? 0) / 1000, 2)} km · ${clock(((r['s'] as num?) ?? 0).toInt(), hours: true)}'),
                  Text('↑ ${elevationGainLoss(_alts(r)).$1.round()} m'),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      AppInfoCard(L(t, 'fg_note'), icon: Icons.screen_lock_portrait_rounded),
      AppInfoCard(L(t, 'walk_privacy'), icon: Icons.lock_rounded),
    ]);
  }
}

/// Hareket: adım sayar, koşu ve bisiklet takibi (yalnız ön planda GPS),
/// ağırlık antrenmanı günlüğü.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../data.dart';
import '../logic.dart';

// ------------------------------------------------------------ adım sayar

class StepsTool extends StatefulWidget {
  final ToolContext t;
  const StepsTool(this.t, {super.key});

  @override
  State<StepsTool> createState() => _StepsToolState();
}

class _StepsToolState extends State<StepsTool> {
  StreamSubscription<StepCount>? _sub;
  bool? _ok;
  int _today = 0, _goal = 8000;
  double _cm = 170, _kg = 70;
  Map<String, Object?> _st = {};
  Map<String, Object?> _days = {};

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _st = await t.store.readMap('state');
    _days = await t.store.readMap('days');
    final cfg = await t.store.readMap('cfg');
    _goal = (cfg['goal'] as num?)?.toInt() ?? _goal;
    _cm = (cfg['cm'] as num?)?.toDouble() ?? _cm;
    _kg = (cfg['kg'] as num?)?.toDouble() ?? _kg;
    _today = (_days[isoDay(DateTime.now())] as num?)?.toInt() ?? 0;
    if (mounted) setState(() {});
    if (kIsWeb) {
      if (mounted) setState(() => _ok = false);
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!mounted) return;
      if (!await rationaleOnce(context, t, 'activity', Icons.directions_walk_rounded)) {
        if (mounted) setState(() => _ok = false);
        return;
      }
      try {
        final s = await Permission.activityRecognition.request();
        if (!s.isGranted) {
          if (mounted) setState(() => _ok = false);
          return;
        }
      } catch (_) {}
    }
    try {
      _sub = Pedometer.stepCountStream.listen(_onCount, onError: (Object _) {
        if (mounted) setState(() => _ok = false);
      }, cancelOnError: true);
    } catch (_) {
      if (mounted) setState(() => _ok = false);
    }
    Timer(const Duration(seconds: 8), () {
      if (mounted && _ok == null) setState(() => _ok = false);
    });
  }

  void _onCount(StepCount e) {
    final day = isoDay(DateTime.now());
    if (_st['day'] != day) _st = {'day': day};
    final r = dailySteps(
      counter: e.steps,
      base: (_st['base'] as num?)?.toInt(),
      carried: (_st['carried'] as num?)?.toInt() ?? 0,
      lastToday: (_st['last'] as num?)?.toInt() ?? 0,
    );
    _st = {'day': day, 'base': r.base, 'carried': r.carried, 'last': r.today};
    _days[day] = r.today;
    final keys = _days.keys.toList()..sort();
    while (keys.length > 120) {
      _days.remove(keys.removeAt(0));
    }
    t.store.writeMap('state', _st);
    t.store.writeMap('days', _days);
    if (mounted) {
      setState(() {
        _ok = true;
        _today = r.today;
      });
    }
  }

  void _saveCfg() => t.store.writeMap('cfg', {'goal': _goal, 'cm': _cm, 'kg': _kg});

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final days = [for (var i = 6; i >= 0; i--) isoDay(DateTime.now().subtract(Duration(days: i)))];
    int v(String d) => (_days[d] as num?)?.toInt() ?? 0;
    final week = days.fold<int>(0, (a, d) => a + v(d));
    return ToolList(children: [
      if (_ok == false) notAvailable(t),
      AppPanel(
        child: Column(children: [
          SizedBox(
            width: 210,
            height: 210,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (_today / _goal).clamp(0.0, 1.0),
                  strokeWidth: 16,
                  backgroundColor: Colors.white12,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.directions_walk_rounded, size: 30),
                Text('$_today', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: s.number)),
                Text('/ $_goal'),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          AppResult(label: L(t, 'distance'), value: '≈ ${fmt(stepsKm(_today, _cm), 2)} km', lang: t.lang),
          AppResult(label: L(t, 'energy'), value: '≈ ${fmt(stepsKcal(_today, _kg), 0)} kcal', lang: t.lang),
        ]),
      ),
      Section(L(t, 'last_7'), icon: Icons.bar_chart_rounded, children: [
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in days)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 90 * (v(d) / math.max<int>(_goal, 1)).clamp(0.02, 1.0),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: v(d) >= _goal ? s.accent : s.accent.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(d.substring(8), style: const TextStyle(fontSize: 11)),
                ]),
              ),
          ]),
        ),
        AppResult(label: L(t, 'total'), value: '$week', lang: t.lang),
      ]),
      Section(L(t, 'settings'), icon: Icons.tune_rounded, children: [
        SliderRow(label: L(t, 'goal'), value: _goal.toDouble(), min: 2000, max: 20000, divisions: 36,
            text: (x) => '${x.round()}', onChanged: (x) {
          setState(() => _goal = x.round());
          _saveCfg();
        }),
        SliderRow(label: L(t, 'height'), value: _cm, min: 120, max: 210, divisions: 90,
            text: (x) => '${x.round()} cm', onChanged: (x) {
          setState(() => _cm = x.roundToDouble());
          _saveCfg();
        }),
        SliderRow(label: L(t, 'weight'), value: _kg, min: 30, max: 200, divisions: 170,
            text: (x) => '${x.round()} kg', onChanged: (x) {
          setState(() => _kg = x.roundToDouble());
          _saveCfg();
        }),
      ]),
      AppInfoCard(L(t, 'steps_hint'), icon: Icons.info_outline_rounded),
    ]);
  }
}

// ------------------------------------------------------ koşu / bisiklet

Future<bool> _locationReady(BuildContext context, ToolContext t) async {
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

/// GPS ile koşu ya da bisiklet. Yalnızca bu ekran açıkken izlenir (arka
/// plan konumu istenmez); ekran açık tutulur.
class TrackTool extends StatefulWidget {
  final ToolContext t;
  final bool bike;
  const TrackTool(this.t, {super.key, this.bike = false});

  @override
  State<TrackTool> createState() => _TrackToolState();
}

class _TrackToolState extends State<TrackTool> {
  StreamSubscription<Position>? _sub;
  bool? _ok;
  bool _recording = false, _paused = false;
  final List<(double, double)> _pts = [];
  double _dist = 0, _max = 0, _speed = 0;
  int _movingMs = 0, _lastMs = 0;
  Timer? _tick;
  List<Map<String, Object?>> _hist = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('sessions').then((h) {
      if (mounted) setState(() => _hist = h);
    });
  }

  Future<void> _start() async {
    final ok = await _locationReady(context, t);
    if (!mounted) return;
    setState(() => _ok = ok);
    if (!ok) return;
    setState(() {
      _recording = true;
      _paused = false;
      _pts.clear();
      _dist = 0;
      _max = 0;
      _speed = 0;
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
      if (!mounted || _paused) return;
      if (p.accuracy > 30) return;
      setState(() {
        if (_pts.isNotEmpty) {
          final d = haversine(_pts.last.$1, _pts.last.$2, p.latitude, p.longitude);
          if (d >= 2 && d < 200) _dist += d;
        }
        _pts.add((p.latitude, p.longitude));
        _speed = p.speed < 0 ? 0.0 : p.speed;
        _max = math.max(_max, _speed);
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
    if (_dist >= 50) {
      final step = math.max<int>(1, _pts.length ~/ 300);
      _hist = <Map<String, Object?>>[
        {
          'at': DateTime.now().millisecondsSinceEpoch,
          'm': _dist.round(),
          's': _movingMs ~/ 1000,
          'max': _max,
          'pts': [for (var i = 0; i < _pts.length; i += step) [_pts[i].$1, _pts[i].$2]],
        },
        ..._hist,
      ].take(100).toList();
      await t.store.writeList('sessions', _hist);
    }
    if (mounted) setState(() => _recording = false);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  String _speedText(double ms) => '${fmt(ms * 3.6)} km/h';

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final secs = _movingMs ~/ 1000;
    final total = _hist.fold<double>(0, (a, h) => a + ((h['m'] as num?) ?? 0).toDouble());
    if (_recording) {
      return ToolList(children: [
        if (_pts.isEmpty) AppInfoCard(L(t, 'waiting_gps'), icon: Icons.satellite_alt_rounded),
        BigReadout(fmt(_dist / 1000, 2), unit: 'km', caption: L(t, 'distance')),
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'duration'), value: clock(secs, hours: true), lang: t.lang),
            if (widget.bike) ...[
              AppResult(label: L(t, 'speed'), value: _speedText(_speed), lang: t.lang),
              AppResult(label: L(t, 'avg_speed'), value: secs > 0 ? _speedText(_dist / secs) : '–', lang: t.lang),
              AppResult(label: L(t, 'maximum'), value: _speedText(_max), lang: t.lang),
            ] else ...[
              AppResult(label: L(t, 'pace'), value: '${pace(secs, _dist)} /km', lang: t.lang),
              AppResult(label: L(t, 'speed'), value: _speedText(_speed), lang: t.lang),
            ],
          ]),
        ),
        if (_pts.length >= 2)
          AppPanel(child: SizedBox(height: 220, child: CustomPaint(size: Size.infinite, painter: RoutePainter(List.of(_pts), s.accent)))),
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
    return ToolList(children: [
      if (_ok == false) notAvailable(t),
      if (_ok == false) AppInfoCard(appTx('perm_denied', t.lang)),
      AppPanel(
        child: Column(children: [
          Icon(widget.bike ? Icons.directions_bike_rounded : Icons.directions_run_rounded, size: 64, color: s.accent),
          AppResult(label: L(t, 'total'), value: '${fmt(total / 1000, 1)} km', lang: t.lang),
          AppResult(label: L(t, 'sessions'), value: '${_hist.length}', lang: t.lang),
          const SizedBox(height: 8),
          AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _start),
        ]),
      ),
      for (final h in _hist.take(20))
        AppPanel(
          child: Row(children: [
            SizedBox(
              width: 90,
              height: 70,
              child: CustomPaint(
                painter: RoutePainter([
                  for (final p in (h['pts'] as List?) ?? const [])
                    if (p is List && p.length == 2) ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
                ], s.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(MaterialLocalizations.of(context).formatMediumDate(DateTime.fromMillisecondsSinceEpoch(((h['at'] as num?) ?? 0).toInt())),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${fmt(((h['m'] as num?) ?? 0) / 1000, 2)} km · ${clock(((h['s'] as num?) ?? 0).toInt(), hours: true)}'),
                Text(widget.bike
                    ? _speedText(((h['m'] as num?) ?? 0) / math.max<num>(1, (h['s'] as num?) ?? 1))
                    : '${pace(((h['s'] as num?) ?? 0).toInt(), ((h['m'] as num?) ?? 0).toDouble())} /km'),
              ]),
            ),
          ]),
        ),
      AppInfoCard(L(t, 'fg_note'), icon: Icons.screen_lock_portrait_rounded),
    ]);
  }
}

/// Rota çizimi (harita karosu yok; çevrimdışı iz).
class RoutePainter extends CustomPainter {
  final List<(double, double)> pts;
  final Color color;
  RoutePainter(this.pts, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final xy = projectRoute(pts, size.width - 12, size.height - 12);
    final path = Path()..moveTo(xy.first.$1 + 6, xy.first.$2 + 6);
    for (final p in xy.skip(1)) {
      path.lineTo(p.$1 + 6, p.$2 + 6);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset(xy.first.$1 + 6, xy.first.$2 + 6), 5, Paint()..color = Colors.greenAccent);
    canvas.drawCircle(Offset(xy.last.$1 + 6, xy.last.$2 + 6), 5, Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.pts.length != pts.length;
}

// -------------------------------------------------------- ağırlık günlüğü

class LiftTool extends StatefulWidget {
  final ToolContext t;
  const LiftTool(this.t, {super.key});

  @override
  State<LiftTool> createState() => _LiftToolState();
}

class _LiftToolState extends State<LiftTool> {
  /// Kayıtlar: {d, ex, kg, reps}
  List<Map<String, Object?>> _sets = [];
  List<String> _custom = [];
  String _ex = kLifts.first;
  final _kg = TextEditingController(), _reps = TextEditingController(text: '10');
  int _rest = 0;
  Timer? _tick;
  final TonePlayer _beep = TonePlayer();

  ToolContext get t => widget.t;
  String get _today => isoDay(DateTime.now());
  String _name(String ex) => ex.startsWith('w_') ? L(t, ex) : ex;

  @override
  void initState() {
    super.initState();
    () async {
      _sets = await t.store.readList('sets');
      _custom = await t.store.readStrings('custom');
      final last = await t.store.read('ex');
      if (last != null) _ex = last;
      if (mounted) setState(() {});
    }();
  }

  Future<void> _addSet() async {
    final kg = numOf(_kg), reps = numOf(_reps)?.round();
    if (kg == null || reps == null || kg < 0 || kg > 1000 || reps < 1 || reps > 200) return;
    setState(() {
      _sets = <Map<String, Object?>>[..._sets, {'d': _today, 'ex': _ex, 'kg': kg, 'reps': reps}];
      if (_sets.length > 5000) _sets = _sets.sublist(_sets.length - 5000);
    });
    await t.store.writeList('sets', _sets);
    await t.store.write('ex', _ex);
  }

  void _startRest(int s) {
    _tick?.cancel();
    setState(() => _rest = s);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_rest <= 1) {
        _tick?.cancel();
        unawaited(_beep.play(beepLong));
        setState(() => _rest = 0);
      } else {
        setState(() => _rest--);
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _beep.dispose();
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = [...kLifts, ..._custom];
    if (!names.contains(_ex)) _ex = names.first;
    final today = [for (final s in _sets) if (s['d'] == _today) s];
    final exToday = <String>[for (final s in today) '${s['ex']}'].toSet().toList();
    double best(String ex) {
      var b = 0.0;
      for (final s in _sets.where((s) => s['ex'] == ex)) {
        b = math.max(b, oneRepMax(((s['kg'] as num?) ?? 0).toDouble(), ((s['reps'] as num?) ?? 1).toInt()));
      }
      return b;
    }

    final byDay = <String, double>{};
    for (final s in _sets) {
      final d = '${s['d']}';
      byDay[d] = (byDay[d] ?? 0) + ((s['kg'] as num?) ?? 0).toDouble() * ((s['reps'] as num?) ?? 0).toInt();
    }
    final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return ToolList(children: [
      Section(L(t, 'add_set'), icon: Icons.fitness_center_rounded, children: [
        Row(children: [
          Expanded(
            child: Pick<String>(label: L(t, 'exercise'), values: names, text: _name, value: _ex, onChanged: (v) => setState(() => _ex = v)),
          ),
          IconButton(
            tooltip: L(t, 'add'),
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () async {
              final c = TextEditingController();
              final n = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(L(t, 'exercise')),
                  content: AppTextField(controller: c, label: L(t, 'name')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L(t, 'cancel'))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(L(t, 'save'))),
                  ],
                ),
              );
              c.dispose();
              if (n == null || n.isEmpty || n.startsWith('w_') || names.contains(n)) return;
              setState(() {
                _custom = [..._custom, n];
                _ex = n;
              });
              await t.store.writeStrings('custom', _custom);
            },
          ),
        ]),
        Row(children: [
          Expanded(child: AppNumberField(controller: _kg, label: L(t, 'weight'), suffix: 'kg', decimal: true)),
          const SizedBox(width: 8),
          Expanded(child: AppNumberField(controller: _reps, label: L(t, 'reps'))),
          IconButton.filled(onPressed: _addSet, icon: const Icon(Icons.check_rounded)),
        ]),
        AppResult(label: L(t, 'best_1rm'), value: '${fmt(best(_ex))} kg', lang: t.lang),
      ]),
      AppPanel(
        child: _rest > 0
            ? Column(children: [
                Text(L(t, 'rest')),
                Text(clock(_rest), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
                TextButton(onPressed: () => _startRest(1), child: Text(L(t, 'skip'))),
              ])
            : Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                Text('${L(t, 'rest_timer')}:'),
                for (final s in const [60, 90, 120, 180]) ActionChip(label: Text(clock(s)), onPressed: () => _startRest(s)),
              ]),
      ),
      if (today.isNotEmpty)
        Section(L(t, 'today'), icon: Icons.today_rounded, children: [
          for (final ex in exToday) ...[
            Text(_name(ex), style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final s in today.where((s) => s['ex'] == ex))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${fmt((s['kg'] as num?) ?? 0)} kg × ${s['reps']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: L(t, 'delete'),
                  onPressed: () async {
                    setState(() => _sets = [for (final x in _sets) if (!identical(x, s)) x]);
                    await t.store.writeList('sets', _sets);
                  },
                ),
              ),
          ],
          AppResult(
            label: L(t, 'volume'),
            value: '${fmt(volume([for (final s in today) (((s['kg'] as num?) ?? 0).toDouble(), ((s['reps'] as num?) ?? 0).toInt())]), 0)} kg',
            lang: t.lang,
          ),
        ]),
      if (dayKeys.length > 1)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final d in dayKeys.where((d) => d != _today).take(20))
            ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(d), trailing: Text('${fmt(byDay[d] ?? 0, 0)} kg')),
        ]),
      AppInfoCard(L(t, 'lift_hint'), icon: Icons.info_outline_rounded),
    ]);
  }
}

/// Uyku sesi günlüğü: gece boyunca mikrofonla ortam sesini izler, belirgin
/// ses olaylarını zamanıyla kaydeder, isteğe bağlı kısa kesitleri sabah
/// dinletir. Kayıtlar ve kesitler yalnızca cihazda kalır.
///
/// Esenlik amaçlıdır: horlama, uyku apnesi ya da başka bir durumu tespit
/// etmez, teşhis koymaz. Ses türü sınıflandırılmaz.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../logic.dart';
import '../platform/clips.dart';
import '../sleep_sound.dart';

class SleepSoundTool extends StatefulWidget {
  final ToolContext t;
  const SleepSoundTool(this.t, {super.key});

  @override
  State<SleepSoundTool> createState() => _SleepSoundToolState();
}

class _SleepSoundToolState extends State<SleepSoundTool> {
  static const int _rate = 16000;
  static const int _maxClips = 40;
  static const int _maxNights = 60;

  /// Hassasiyet: düşük / orta / yüksek → ortamın kaç dB üstü.
  static const List<double> _thresholds = [14, 10, 7];

  List<NightRecord> _nights = [];
  bool _loaded = false;
  int _sens = 1;
  bool _keepClips = true;
  String? _open;
  String? _error;

  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  SoundDetector? _det;
  DateTime? _recStart;
  String _recId = '';
  final List<int> _carry = [];
  final Map<int, String> _clipNames = {};
  Timer? _tick;

  final TonePlayer _player = TonePlayer();

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    () async {
      final n = (await t.store.readList('nights')).map(NightRecord.fromJson).whereType<NightRecord>().toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      final sens = await t.store.readInt('sens', 1);
      final keep = await t.store.readBool('keep_clips', true);
      await ClipStore.prune({for (final x in n) for (final e in x.events) if (e.clip.isNotEmpty) e.clip});
      if (mounted) {
        setState(() {
          _nights = n;
          _sens = sens.clamp(0, 2);
          _keepClips = keep;
          _loaded = true;
        });
      }
    }();
  }

  @override
  void dispose() {
    if (_det != null) unawaited(_stop());
    _player.dispose();
    super.dispose();
  }

  Future<void> _save() => t.store.writeList('nights', [for (final x in _nights) x.toJson()]);

  // ------------------------------------------------------------ kayıt

  Future<void> _start() async {
    if (!await rationaleOnce(context, t, 'mic', Icons.mic_rounded)) return;
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        await rec.dispose();
        if (mounted) setState(() => _error = appTx('perm_denied', t.lang));
        return;
      }
      final stream = await rec.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _rate, numChannels: 1),
      );
      final id = '${DateTime.now().millisecondsSinceEpoch}';
      final det = SoundDetector(rate: _rate, threshold: _thresholds[_sens]);
      det.onEvent = (e, pcm) => _onEvent(id, det, pcm);
      _carry.clear();
      _clipNames.clear();
      _sub = stream.listen((d) => det.add(pcmBytes(d, _carry)));
      _rec = rec;
      unawaited(WakelockPlus.enable().catchError((Object _) {}));
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (mounted) {
        setState(() {
          _det = det;
          _recId = id;
          _recStart = DateTime.now();
          _error = null;
          _open = null;
        });
      }
    } catch (_) {
      try {
        await rec.dispose();
      } catch (_) {}
      if (mounted) setState(() => _error = L(t, 'ss_error'));
    }
  }

  void _onEvent(String id, SoundDetector det, Int16List pcm) {
    if (!_keepClips || _clipNames.length >= _maxClips || pcm.isEmpty) return;
    final idx = det.events.length - 1;
    final name = '${id}_$idx.wav';
    _clipNames[idx] = name;
    unawaited(ClipStore.save(name, pcmToWav(pcm, _rate)));
  }

  Future<void> _stop() async {
    final det = _det;
    if (det == null) return;
    _det = null;
    _tick?.cancel();
    await _sub?.cancel();
    _sub = null;
    final rec = _rec;
    _rec = null;
    if (rec != null) {
      try {
        await rec.stop();
      } catch (_) {}
      try {
        await rec.dispose();
      } catch (_) {}
    }
    det.close();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    final start = _recStart ?? DateTime.now();
    final end = DateTime.now();
    final events = [
      for (var i = 0; i < det.events.length; i++)
        _clipNames[i] == null ? det.events[i] : det.events[i].withClip(_clipNames[i]!),
    ];
    if (end.difference(start).inMinutes < 1) {
      for (final c in _clipNames.values) {
        await ClipStore.delete(c);
      }
      if (mounted) setState(() => _error = L(t, 'ss_too_short'));
      return;
    }
    final night = NightRecord(id: _recId, start: start, end: end, events: events, levels: List.of(det.levels));
    var all = [night, ..._nights];
    if (all.length > _maxNights) {
      for (final old in all.sublist(_maxNights)) {
        for (final e in old.events) {
          if (e.clip.isNotEmpty) await ClipStore.delete(e.clip);
        }
      }
      all = all.sublist(0, _maxNights);
    }
    _nights = all;
    await _save();
    if (mounted) setState(() => _open = night.id);
  }

  Future<void> _play(SoundEvent e) async {
    final bytes = await ClipStore.read(e.clip);
    if (bytes == null) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'ss_clip_missing'))));
      return;
    }
    await _player.play(bytes);
  }

  Future<void> _delete(NightRecord n) async {
    if (!await confirm(context, t, L(t, 'ss_delete_night'))) return;
    for (final e in n.events) {
      if (e.clip.isNotEmpty) await ClipStore.delete(e.clip);
    }
    _nights = [for (final x in _nights) if (x.id != n.id) x];
    await _save();
    if (mounted) setState(() => _open = null);
  }

  void _update(NightRecord n) {
    setState(() => _nights = [for (final x in _nights) x.id == n.id ? n : x]);
    unawaited(_save());
  }

  Future<void> _editNote(NightRecord n) async {
    final c = TextEditingController(text: n.note);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(L(t, 'ss_note')),
        content: AppTextField(controller: c, label: L(t, 'ss_note'), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t.core('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(t.core('ok'))),
        ],
      ),
    );
    c.dispose();
    if (v != null) _update(n.copyWith(note: v));
  }

  // ------------------------------------------------------------ biçim

  String _hm(DateTime d) => TimeOfDay.fromDateTime(d).format(context);

  String _dur(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

  String _nightTitle(NightRecord n) => '${MaterialLocalizations.of(context).formatMediumDate(n.start)} · ${_hm(n.start)}–${_hm(n.end)}';

  // ------------------------------------------------------------ görünüm

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final det = _det;
    if (det != null) return _recordingView(det);
    NightRecord? open;
    for (final n in _nights) {
      if (n.id == _open) open = n;
    }
    return open == null ? _listView() : _detailView(open);
  }

  Widget _recordingView(SoundDetector det) {
    final start = _recStart ?? DateTime.now();
    final elapsed = DateTime.now().difference(start);
    return Container(
      color: Colors.black,
      child: ToolList(children: [
        const SizedBox(height: 24),
        Center(
          child: Text(_hm(DateTime.now()),
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300, color: Colors.white38)),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.fiber_manual_record_rounded, size: 14, color: Colors.redAccent.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Flexible(child: Text(L(t, 'ss_recording'), style: const TextStyle(color: Colors.white54))),
        ]),
        const SizedBox(height: 16),
        Center(
          child: Text('${clock(elapsed.inSeconds, hours: true)} · ${L(t, 'ss_events')}: ${det.events.length}${det.active ? ' •' : ''}',
              style: const TextStyle(color: Colors.white38)),
        ),
        const SizedBox(height: 24),
        AppInfoCard(L(t, 'ss_keep_open'), icon: Icons.screen_lock_portrait_rounded),
        Center(child: AppButton(label: L(t, 'ss_stop'), icon: Icons.stop_rounded, onPressed: _stop)),
      ]),
    );
  }

  Widget _listView() {
    final supported = ClipStore.supported;
    final recent = _nights.take(7).toList();
    final avgPerHour = recent.isEmpty ? 0.0 : recent.fold<double>(0, (a, n) => a + n.perHour) / recent.length;
    final avgSound = recent.isEmpty ? 0 : recent.fold<int>(0, (a, n) => a + n.soundSeconds) ~/ recent.length;
    return ToolList(children: [
      AppInfoCard(L(t, 'ss_disclaimer'), icon: Icons.health_and_safety_rounded),
      if (!supported) notAvailable(t),
      if (_error != null) AppInfoCard(_error!, icon: Icons.error_outline_rounded),
      if (supported)
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(L(t, 'ss_sensitivity'), style: const TextStyle(fontWeight: FontWeight.w800)),
            Choice<int>(
              values: const [0, 1, 2],
              labels: [L(t, 'ss_sens_low'), L(t, 'ss_sens_mid'), L(t, 'ss_sens_high')],
              selected: _sens,
              onChanged: (v) {
                setState(() => _sens = v);
                unawaited(t.store.write('sens', '$v'));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L(t, 'ss_keep_clips')),
              subtitle: Text(L(t, 'ss_clips_note')),
              value: _keepClips,
              onChanged: (b) {
                setState(() => _keepClips = b);
                unawaited(t.store.writeBool('keep_clips', b));
              },
            ),
            Center(child: AppButton(label: L(t, 'ss_start'), icon: Icons.nightlight_round, onPressed: _start)),
          ]),
        ),
      if (supported) AppInfoCard(L(t, 'ss_tips'), icon: Icons.tips_and_updates_rounded),
      if (recent.isNotEmpty)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'ss_avg_per_hour'), value: avgPerHour.toStringAsFixed(1), lang: t.lang),
            AppResult(label: L(t, 'ss_avg_sound'), value: clock(avgSound), lang: t.lang),
          ]),
        ),
      if (_nights.isNotEmpty) AppHeading(L(t, 'ss_nights'), icon: Icons.bedtime_rounded),
      for (final n in _nights)
        Card(
          child: ListTile(
            leading: const Icon(Icons.nights_stay_rounded),
            title: Text(_nightTitle(n), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_dur(n.minutes)} · ${L(t, 'ss_events')}: ${n.events.length} · ${L(t, 'ss_sound_time')}: ${clock(n.soundSeconds)}'),
            onTap: () => setState(() => _open = n.id),
          ),
        ),
      AppInfoCard(L(t, 'ss_privacy'), icon: Icons.lock_rounded),
    ]);
  }

  Widget _detailView(NightRecord n) {
    final factors = Ls(t, 'ss_factors');
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(onPressed: () => setState(() => _open = null), icon: const BackButtonIcon()),
          Expanded(child: Text(_nightTitle(n), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'ss_duration'), value: _dur(n.minutes), lang: t.lang, big: true),
          AppResult(label: L(t, 'ss_events'), value: '${n.events.length}', lang: t.lang),
          AppResult(label: L(t, 'ss_per_hour'), value: n.perHour.toStringAsFixed(1), lang: t.lang),
          AppResult(label: L(t, 'ss_sound_time'), value: clock(n.soundSeconds), lang: t.lang),
          AppResult(label: L(t, 'ss_quiet'), value: '%${(n.quietShare * 100).round()}', lang: t.lang),
        ]),
      ),
      if (n.levels.length > 1)
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(L(t, 'ss_timeline'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: CustomPaint(size: Size.infinite, painter: _LevelsPainter(n.levels, AppLook.of(context).accent)),
            ),
            Row(children: [
              Text(_hm(n.start), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              Text(_hm(n.end), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ]),
        ),
      AppHeading(L(t, 'ss_factors_title'), icon: Icons.checklist_rounded),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 6, runSpacing: 2, children: [
          for (var i = 0; i < factors.length; i++)
            FilterChip(
              label: Text(factors[i]),
              selected: n.factors.contains(i),
              onSelected: (b) => _update(n.copyWith(factors: b ? [...n.factors, i] : [for (final x in n.factors) if (x != i) x])),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListTile(
          leading: const Icon(Icons.edit_note_rounded),
          title: Text(n.note.isEmpty ? L(t, 'ss_note') : n.note),
          onTap: () => _editNote(n),
        ),
      ),
      if (n.events.isNotEmpty) AppHeading(L(t, 'ss_events'), icon: Icons.graphic_eq_rounded),
      for (final e in n.events.take(300))
        Card(
          child: ListTile(
            leading: const Icon(Icons.graphic_eq_rounded),
            title: Text(_hm(n.start.add(Duration(seconds: e.at)))),
            subtitle: Text('${clock(e.dur)} · +${e.peak.round()} dB'),
            trailing: e.clip.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.play_circle_rounded), tooltip: L(t, 'ss_play'), onPressed: () => _play(e)),
          ),
        ),
      Center(
        child: TextButton.icon(
          onPressed: () => _delete(n),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(L(t, 'ss_delete_night')),
        ),
      ),
      AppInfoCard(L(t, 'ss_disclaimer'), icon: Icons.health_and_safety_rounded),
    ]);
  }
}

/// Dakika başına ses düzeyi çubukları.
class _LevelsPainter extends CustomPainter {
  final List<int> levels;
  final Color color;
  _LevelsPainter(this.levels, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final hi = math.max(20, levels.reduce(math.max)).toDouble();
    final w = size.width / levels.length;
    final p = Paint()..color = color;
    for (var i = 0; i < levels.length; i++) {
      final h = levels[i] / hi * size.height;
      if (h <= 0) continue;
      canvas.drawRect(Rect.fromLTWH(i * w, size.height - h, math.max(1.0, w * 0.8), h), p);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = Colors.white24);
  }

  @override
  bool shouldRepaint(_LevelsPainter old) => old.levels != levels || old.color != color;
}

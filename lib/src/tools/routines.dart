/// Zamanlı rutinler: aralıklı antrenman, ev egzersizi, esneme, yoga, göz
/// egzersizi, nefes ve çocuklar için diş fırçalama.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../data.dart';
import '../logic.dart';
import '../platform/notify.dart';

// ------------------------------------------------------------------ HIIT

class HiitTool extends StatefulWidget {
  final ToolContext t;
  const HiitTool(this.t, {super.key});

  @override
  State<HiitTool> createState() => _HiitToolState();
}

class _HiitToolState extends State<HiitTool> {
  int _work = 30, _rest = 15, _rounds = 8, _prep = 10;
  List<Phase>? _plan;
  int _elapsedMs = 0, _lastMs = 0, _lastLeft = -1;
  bool _running = false;
  Timer? _tick;
  final TonePlayer _beep = TonePlayer();

  ToolContext get t => widget.t;

  static const _presets = [(20, 10, 8), (30, 30, 10), (45, 15, 8), (40, 20, 6)];

  @override
  void initState() {
    super.initState();
    t.store.readMap('cfg').then((m) {
      if (!mounted) return;
      setState(() {
        _work = (m['work'] as num?)?.toInt() ?? _work;
        _rest = (m['rest'] as num?)?.toInt() ?? _rest;
        _rounds = (m['rounds'] as num?)?.toInt() ?? _rounds;
        _prep = (m['prep'] as num?)?.toInt() ?? _prep;
      });
    });
  }

  void _save() => t.store.writeMap('cfg', {'work': _work, 'rest': _rest, 'rounds': _rounds, 'prep': _prep});

  void _start() {
    _save();
    setState(() {
      _plan = buildIntervals(work: _work, rest: _rest, rounds: _rounds, prep: _prep);
      _elapsedMs = 0;
      _running = true;
      _lastMs = DateTime.now().millisecondsSinceEpoch;
    });
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
  }

  void _onTick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_running) _elapsedMs += now - _lastMs;
    _lastMs = now;
    final plan = _plan;
    if (plan == null) return;
    final at = phaseAt(plan, _elapsedMs ~/ 1000);
    if (at == null) {
      unawaited(_beep.play(beepLong));
      _finish(done: true);
      return;
    }
    if (at.left != _lastLeft) {
      if (at.left <= 3 && at.left >= 1) unawaited(_beep.play(beepShort));
      _lastLeft = at.left;
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish({bool done = false}) async {
    _tick?.cancel();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    if (done) {
      final n = await t.store.readInt('sessions');
      await t.store.write('sessions', '${n + 1}');
    }
    if (mounted) setState(() => _plan = null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _beep.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    if (plan != null) {
      final at = phaseAt(plan, _elapsedMs ~/ 1000);
      if (at == null) return const SizedBox.shrink();
      final ph = plan[at.index];
      final colors = [Colors.amber, Colors.redAccent, Colors.lightBlueAccent];
      final name = [L(t, 'get_ready'), L(t, 'work'), L(t, 'rest')][ph.kind];
      final left = totalSeconds(plan) - _elapsedMs ~/ 1000;
      return ToolList(children: [
        AppPanel(
          child: Column(children: [
            Text(name, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: colors[ph.kind])),
            if (ph.round > 0) Text(Lf(t, 'round_x', {'n': ph.round, 'm': _rounds}), style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: at.left / math.max<int>(1, ph.seconds),
                    strokeWidth: 14,
                    color: colors[ph.kind],
                    backgroundColor: Colors.white12,
                  ),
                ),
                Text('${at.left}', style: TextStyle(fontSize: 80, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
              ]),
            ),
            const SizedBox(height: 10),
            AppResult(label: L(t, 'total_left'), value: clock(left), lang: t.lang),
          ]),
        ),
        Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
          AppButton(
            label: L(t, _running ? 'pause' : 'resume'),
            icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPressed: () => setState(() => _running = !_running),
          ),
          AppButton(label: L(t, 'stop'), icon: Icons.stop_rounded, onPressed: () => _finish()),
        ]),
      ]);
    }
    final total = totalSeconds(buildIntervals(work: _work, rest: _rest, rounds: _rounds, prep: _prep));
    return ToolList(children: [
      Section(L(t, 'presets'), icon: Icons.bolt_rounded, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _presets)
            ActionChip(
              label: Text('${p.$1}/${p.$2} × ${p.$3}'),
              onPressed: () => setState(() {
                _work = p.$1;
                _rest = p.$2;
                _rounds = p.$3;
              }),
            ),
        ]),
      ]),
      Section(L(t, 'settings'), icon: Icons.tune_rounded, children: [
        SliderRow(
            label: L(t, 'work'), value: _work.toDouble(), min: 5, max: 180, divisions: 35,
            text: (v) => '${v.round()} s', onChanged: (v) => setState(() => _work = v.round())),
        SliderRow(
            label: L(t, 'rest'), value: _rest.toDouble(), min: 0, max: 180, divisions: 36,
            text: (v) => '${v.round()} s', onChanged: (v) => setState(() => _rest = v.round())),
        SliderRow(
            label: L(t, 'rounds'), value: _rounds.toDouble(), min: 1, max: 30, divisions: 29,
            text: (v) => '${v.round()}', onChanged: (v) => setState(() => _rounds = v.round())),
        SliderRow(
            label: L(t, 'get_ready'), value: _prep.toDouble(), min: 0, max: 30, divisions: 6,
            text: (v) => '${v.round()} s', onChanged: (v) => setState(() => _prep = v.round())),
        AppResult(label: L(t, 'total'), value: clock(total), lang: t.lang),
      ]),
      Center(child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _start)),
      AppInfoCard(L(t, 'exercise_hint'), icon: Icons.favorite_border_rounded),
    ]);
  }
}

// ------------------------------------------------- egzersiz / esneme / yoga

/// [kind]: 'workout', 'stretch' ya da 'yoga'.
class RoutineTool extends StatefulWidget {
  final ToolContext t;
  final String kind;
  const RoutineTool(this.t, {super.key, required this.kind});

  @override
  State<RoutineTool> createState() => _RoutineToolState();
}

class _RoutineToolState extends State<RoutineTool> {
  Routine? _active;
  bool _justDone = false;
  List<String> _days = [];

  ToolContext get t => widget.t;

  List<Routine> get _list => switch (widget.kind) { 'stretch' => kStretches, 'yoga' => kYoga, _ => kWorkouts };

  @override
  void initState() {
    super.initState();
    t.store.readStrings('days').then((d) {
      if (mounted) setState(() => _days = d);
    });
  }

  Future<void> _done(bool completed) async {
    if (completed) {
      final today = isoDay(DateTime.now());
      if (!_days.contains(today)) {
        _days = [..._days, today];
        if (_days.length > 400) _days = _days.sublist(_days.length - 400);
        await t.store.writeStrings('days', _days);
      }
    }
    if (mounted) {
      setState(() {
        _active = null;
        _justDone = completed;
      });
    }
  }

  Widget _card(Routine r) => AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(L(t, r.key), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            Text(clock(r.seconds)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final s in r.steps)
                SizedBox(
                  width: 84,
                  child: Column(children: [
                    SizedBox(
                      height: 56,
                      child: CustomPaint(
                        size: const Size(56, 56),
                        painter: FigurePainter(exercise(s.$1).a, null, 0, AppLook.of(context).accent),
                      ),
                    ),
                    Text(L(t, 'ex_${s.$1}'), maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
            ]),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: L(t, 'start'),
              icon: Icons.play_arrow_rounded,
              onPressed: () => setState(() {
                _active = r;
                _justDone = false;
              }),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final a = _active;
    if (a != null) {
      return ToolList(children: [RoutinePlayer(tool: t, routine: a, onDone: _done)]);
    }
    return ToolList(children: [
      if (_justDone) AppInfoCard(L(t, 'well_done'), icon: Icons.emoji_events_rounded),
      AppPanel(
        child: Row(children: [
          Expanded(child: AppResult(label: L(t, 'streak'), value: '${streak(_days, DateTime.now())}', lang: t.lang)),
          Expanded(child: AppResult(label: L(t, 'sessions'), value: '${_days.length}', lang: t.lang)),
        ]),
      ),
      for (final r in _list.where((r) => !r.extra)) _card(r),
      for (final r in _list.where((r) => r.extra))
        ExtraGate(tool: t, feature: 'routine_${r.key}', child: _card(r)),
      AppInfoCard(L(t, widget.kind == 'yoga' ? 'yoga_hint' : 'exercise_hint'), icon: Icons.favorite_border_rounded),
    ]);
  }

}

// --------------------------------------------------------------- göz

class EyeTool extends StatefulWidget {
  final ToolContext t;
  const EyeTool(this.t, {super.key});

  @override
  State<EyeTool> createState() => _EyeToolState();
}

class _EyeToolState extends State<EyeTool> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  int? _step;
  int _left = 0;
  Timer? _tick;
  bool _remind = false;
  int _from = 9 * 60, _to = 18 * 60;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('remind').then((m) {
      if (!mounted) return;
      setState(() {
        _remind = m['on'] == true;
        _from = (m['from'] as num?)?.toInt() ?? _from;
        _to = (m['to'] as num?)?.toInt() ?? _to;
      });
    });
  }

  void _go(int i) {
    _tick?.cancel();
    if (i >= kEyeSteps.length) {
      _anim.stop();
      setState(() => _step = null);
      return;
    }
    setState(() {
      _step = i;
      _left = kEyeSteps[i].$2;
    });
    _anim.repeat();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        HapticFeedback.lightImpact();
        _go(i + 1);
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _setRemind(bool on) async {
    if (on) await askNotifyOnce(context, t);
    setState(() => _remind = on);
    await t.store.writeMap('remind', {'on': on, 'from': _from, 'to': _to});
    if (on) {
      await scheduleDaily(base: 31000, minutes: reminderSlots(_from, _to, 20), title: L(t, 'n_eye_title'), body: L(t, 'rule_2020'));
    } else {
      await cancelDaily(31000);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _step;
    if (st != null) {
      final key = kEyeSteps[st].$1;
      return ToolList(children: [
        AppPanel(
          child: Column(children: [
            Text(L(t, 'ex_$key'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(size: Size.infinite, painter: _EyeGuide(key, _anim.value, AppLook.of(context).accent)),
              ),
            ),
            Text('$_left', style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
            Text(Lf(t, 'step_x', {'n': st + 1, 'm': kEyeSteps.length})),
          ]),
        ),
        Center(child: AppButton(label: L(t, 'stop'), icon: Icons.stop_rounded, onPressed: () => _go(kEyeSteps.length))),
      ]);
    }
    return ToolList(children: [
      AppInfoCard(L(t, 'rule_2020'), icon: Icons.visibility_rounded),
      Section(L(t, 'routine'), icon: Icons.remove_red_eye_rounded, children: [
        for (final s in kEyeSteps)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(L(t, 'ex_${s.$1}')), trailing: Text('${s.$2} s')),
        Center(child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: () => _go(0))),
      ]),
      Section(L(t, 'reminders'), icon: Icons.notifications_rounded, children: [
        if (!Notify.supported) notAvailable(t),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L(t, 'remind_2020')),
          value: _remind,
          onChanged: Notify.supported ? _setRemind : null,
        ),
        TimeRow(label: L(t, 'from'), minute: _from, onChanged: (v) => setState(() => _from = v)),
        TimeRow(label: L(t, 'to'), minute: _to, onChanged: (v) => setState(() => _to = v)),
        if (_remind)
          TextButton(onPressed: () => _setRemind(true), child: Text(L(t, 'apply'))),
      ]),
      AppInfoCard(L(t, 'eye_hint'), icon: Icons.info_outline_rounded),
    ]);
  }
}

class _EyeGuide extends CustomPainter {
  final String key;
  final double v;
  final Color color;
  _EyeGuide(this.key, this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * 0.4;
    final ph = v * 2 * math.pi;
    var p = c;
    var dot = 14.0;
    switch (key) {
      case 'eye_lr':
        p = c + Offset(math.sin(ph) * r * 1.2, 0);
      case 'eye_ud':
        p = c + Offset(0, math.sin(ph) * r);
      case 'eye_circle':
        p = c + Offset(math.cos(ph) * r, math.sin(ph) * r);
      case 'eye_focus':
        dot = 8 + 22 * (0.5 + 0.5 * math.sin(ph));
      case 'eye_far':
        dot = 6;
      case 'eye_blink':
        final open = (math.sin(ph * 2) > -0.6) ? 1.0 : 0.15;
        final eye = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawOval(Rect.fromCenter(center: c, width: r * 1.6, height: r * 0.8 * open), eye);
        if (open > 0.5) canvas.drawCircle(c, r * 0.22, Paint()..color = color);
        return;
    }
    canvas.drawCircle(c, 3, Paint()..color = Colors.white24);
    canvas.drawCircle(p, dot, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EyeGuide old) => old.v != v || old.key != key;
}

// --------------------------------------------------------------- nefes

class BreathTool extends StatefulWidget {
  final ToolContext t;
  const BreathTool(this.t, {super.key});

  @override
  State<BreathTool> createState() => _BreathToolState();
}

class _BreathToolState extends State<BreathTool> {
  int _pattern = 0;
  int _minutes = 3;
  bool _running = false;
  int _startMs = 0;
  Timer? _tick;
  int _lastPhase = -1;

  ToolContext get t => widget.t;

  List<(int, int)> _phases() {
    final p = kBreaths[_pattern];
    return [(0, p.$2), if (p.$3 > 0) (1, p.$3), (2, p.$4), if (p.$5 > 0) (3, p.$5)];
  }

  void _start() {
    setState(() {
      _running = true;
      _startMs = DateTime.now().millisecondsSinceEpoch;
      _lastPhase = -1;
    });
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final el = DateTime.now().millisecondsSinceEpoch - _startMs;
      if (el >= _minutes * 60000) {
        _stop(done: true);
        return;
      }
      setState(() {});
    });
  }

  Future<void> _stop({bool done = false}) async {
    _tick?.cancel();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    if (done) {
      final days = await t.store.readStrings('days');
      final today = isoDay(DateTime.now());
      if (!days.contains(today)) await t.store.writeStrings('days', [...days, today]);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    if (_running) {
      final ph = _phases();
      final cycle = ph.fold<int>(0, (a, b) => a + b.$2) * 1000;
      final el = DateTime.now().millisecondsSinceEpoch - _startMs;
      var x = el % cycle;
      var i = 0;
      while (x >= ph[i].$2 * 1000) {
        x -= ph[i].$2 * 1000;
        i++;
      }
      final f = x / (ph[i].$2 * 1000);
      if (i != _lastPhase) {
        _lastPhase = i;
        HapticFeedback.selectionClick();
      }
      final kind = ph[i].$1;
      final scale = switch (kind) { 0 => 0.45 + 0.55 * f, 1 => 1.0, 2 => 1.0 - 0.55 * f, _ => 0.45 };
      final label = L(t, ['inhale', 'hold', 'exhale', 'hold'][kind]);
      final left = _minutes * 60 - el ~/ 1000;
      return ToolList(children: [
        AppPanel(
          child: Column(children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Container(
                  width: 280 * scale,
                  height: 280 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [s.accent.withValues(alpha: 0.9), s.accent.withValues(alpha: 0.25)]),
                  ),
                  alignment: Alignment.center,
                  child: Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
            ),
            Text('${ph[i].$2 - x ~/ 1000}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: s.number)),
            AppResult(label: L(t, 'total_left'), value: clock(left), lang: t.lang),
          ]),
        ),
        Center(child: AppButton(label: L(t, 'stop'), icon: Icons.stop_rounded, onPressed: () => _stop())),
      ]);
    }
    return ToolList(children: [
      Section(L(t, 'pattern'), icon: Icons.air_rounded, children: [
        for (var i = 0; i < kBreaths.length; i++)
          RadioListTile<int>(
            contentPadding: EdgeInsets.zero,
            value: i,
            groupValue: _pattern,
            onChanged: (v) => setState(() => _pattern = v ?? 0),
            title: Text(L(t, kBreaths[i].$1)),
            subtitle: Text([kBreaths[i].$2, kBreaths[i].$3, kBreaths[i].$4, kBreaths[i].$5].where((x) => x > 0).join(' · ')),
          ),
        SliderRow(
          label: L(t, 'duration'),
          value: _minutes.toDouble(),
          min: 1,
          max: 15,
          divisions: 14,
          text: (v) => '${v.round()} ${L(t, 'min_short')}',
          onChanged: (v) => setState(() => _minutes = v.round()),
        ),
      ]),
      Center(child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _start)),
      WarnCard(L(t, 'breath_hint')),
    ]);
  }
}

// -------------------------------------------------------- diş fırçalama

/// Çocuklar için 2 dakikalık fırçalama oyunu. Families politikası: bu
/// araçta reklam gösterilmez, ödüllü reklam ya da satın alma yoktur;
/// açıkken ve çıkarken geçiş reklamı zamanlayıcısı sıfırlanır, böylece
/// merkezin "doğal ara" reklamı da bu araçtan sonra gösterilmez.
class ToothbrushTool extends StatefulWidget {
  final ToolContext t;
  const ToothbrushTool(this.t, {super.key});

  @override
  State<ToothbrushTool> createState() => _ToothbrushToolState();
}

class _ToothbrushToolState extends State<ToothbrushTool> with SingleTickerProviderStateMixin {
  static const int _quarter = 30;
  late final AnimationController _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  Timer? _tick, _noAds;
  int _left = 0;
  bool _running = false;
  List<String> _days = [];
  final TonePlayer _beep = TonePlayer();

  ToolContext get t => widget.t;

  void _quietAds() => t.services.lastInterstitialMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _quietAds();
    _noAds = Timer.periodic(const Duration(seconds: 20), (_) => _quietAds());
    t.store.readStrings('days').then((d) {
      if (mounted) setState(() => _days = d);
    });
  }

  void _start() {
    setState(() {
      _running = true;
      _left = _quarter * 4;
    });
    _wiggle.repeat(reverse: true);
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_left <= 1) {
        _tick?.cancel();
        _wiggle.stop();
        unawaited(_beep.play(makeWav([(523, 150), (659, 150), (784, 150), (1046, 400)], volume: 0.6)));
        final today = isoDay(DateTime.now());
        if (!_days.contains(today)) {
          _days = [..._days, today];
          await t.store.writeStrings('days', _days);
        }
        unawaited(WakelockPlus.disable().catchError((Object _) {}));
        if (mounted) setState(() => _running = false);
        return;
      }
      setState(() => _left--);
      if (_left % _quarter == 0) unawaited(_beep.play(beepShort));
    });
  }

  @override
  void dispose() {
    _quietAds();
    _tick?.cancel();
    _noAds?.cancel();
    _wiggle.dispose();
    _beep.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final q = _running ? (4 - (_left - 1) ~/ _quarter - 1).clamp(0, 3) : -1;
    final names = ['brush_ul', 'brush_ur', 'brush_ll', 'brush_lr'];
    final week = [
      for (var i = 6; i >= 0; i--) _days.contains(isoDay(DateTime.now().subtract(Duration(days: i)))),
    ];
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Text(_running ? L(t, names[q]) : L(t, 'brush_ready'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          SizedBox(
            height: 240,
            child: AnimatedBuilder(
              animation: _wiggle,
              builder: (_, __) => CustomPaint(size: Size.infinite, painter: _MouthPainter(q, _wiggle.value, s.accent)),
            ),
          ),
          if (_running) Text(clock(_left), style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: s.number)),
        ]),
      ),
      if (!_running) Center(child: AppButton(label: L(t, 'brush_go'), icon: Icons.brush_rounded, onPressed: _start)),
      AppPanel(
        child: Column(children: [
          Text(L(t, 'stars_week'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final w in week) Icon(w ? Icons.star_rounded : Icons.star_border_rounded, color: w ? Colors.amber : Colors.white38, size: 34),
          ]),
        ]),
      ),
      AppInfoCard(L(t, 'brush_parent'), icon: Icons.family_restroom_rounded),
    ]);
  }
}

class _MouthPainter extends CustomPainter {
  final int active;
  final double w;
  final Color color;
  _MouthPainter(this.active, this.w, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final tw = math.min(size.width / 9, 34.0), th = tw * 1.3;
    for (var row = 0; row < 2; row++) {
      for (var i = 0; i < 8; i++) {
        final quadrant = row * 2 + (i < 4 ? 0 : 1);
        final on = quadrant == active;
        final x = c.dx + (i - 4) * (tw + 4) + 2;
        final y = row == 0 ? c.dy - th - 6 : c.dy + 6;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, tw, th), Radius.circular(tw / 3));
        canvas.drawRRect(r, Paint()..color = on ? Colors.white : Colors.white70);
        if (on) {
          canvas.drawRRect(r, Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
        }
      }
    }
    if (active >= 0) {
      // fırça ve köpük kabarcıkları
      final left = active % 2 == 0;
      final top = active < 2;
      final bx = c.dx + (left ? -2 : 2) * (tw + 4) + (w - 0.5) * tw * 1.4;
      final by = top ? c.dy - th - 22 : c.dy + th + 22;
      final brush = Paint()
        ..color = color
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(bx - 40, by), Offset(bx + 40, by), brush);
      for (var k = 0; k < 6; k++) {
        final a = k * 1.1 + w * 3;
        canvas.drawCircle(Offset(bx + math.cos(a) * 30, by + (top ? 14 : -14) + math.sin(a) * 8), 5 + (k % 3) * 2.0,
            Paint()..color = Colors.lightBlueAccent.withValues(alpha: 0.7));
      }
    }
  }

  @override
  bool shouldRepaint(_MouthPainter old) => old.active != active || old.w != w;
}

/// Duvar pilatesi: kodla çizilmiş duvar + çöp adam hareketleri, 28 günlük
/// plan ve serbest rutinler. Esenlik amaçlıdır; tıbbi iddia yoktur.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../data.dart';
import '../logic.dart';

class WallPilatesTool extends StatefulWidget {
  final ToolContext t;
  const WallPilatesTool(this.t, {super.key});

  @override
  State<WallPilatesTool> createState() => _WallPilatesToolState();
}

class _WallPilatesToolState extends State<WallPilatesTool> {
  Routine? _active;
  bool _justDone = false;
  List<String> _days = [];
  DateTime? _start;
  String? _openEx;

  ToolContext get t => widget.t;

  static List<Exercise> get _moves => [for (final e in kExercises) if (e.key.startsWith('wp_')) e];

  @override
  void initState() {
    super.initState();
    () async {
      final d = await t.store.readStrings('days');
      final s = await t.store.read('plan_start');
      if (mounted) {
        setState(() {
          _days = d;
          _start = s == null ? null : DateTime.tryParse(s);
        });
      }
    }();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Planın bugünkü günü (0..27); plan bittiyse 28.
  int? get _planDay {
    final s = _start;
    if (s == null) return null;
    return math.min(28, math.max(0, _today.difference(DateTime(s.year, s.month, s.day)).inDays));
  }

  Future<void> _startPlan() async {
    final d = _today;
    await t.store.write('plan_start', isoDay(d));
    if (mounted) setState(() => _start = d);
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

  void _play(Routine r) => setState(() {
        _active = r;
        _justDone = false;
      });

  Widget _thumbs(Routine r) => SizedBox(
        height: 60 + MediaQuery.textScalerOf(context).scale(11) * 1.3 * 2 + 4,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final s in r.steps)
            SizedBox(
              width: 84,
              child: Column(children: [
                SizedBox(
                  height: 56,
                  child: CustomPaint(
                    size: const Size(56, 56),
                    painter: FigurePainter(exercise(s.$1).a, null, 0, AppLook.of(context).accent, wall: exercise(s.$1).wall),
                  ),
                ),
                Text(L(t, 'ex_${s.$1}'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
              ]),
            ),
        ]),
      );

  Widget _card(Routine r, {String? title}) => AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title ?? L(t, r.key), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            Text(clock(r.seconds)),
          ]),
          const SizedBox(height: 8),
          _thumbs(r),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: () => _play(r)),
          ),
        ]),
      );

  Widget _plan() {
    final day = _planDay;
    if (day == null) {
      return AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(L(t, 'wp_plan'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(L(t, 'wp_plan_hint')),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(label: L(t, 'wp_plan_start'), icon: Icons.flag_rounded, onPressed: _startPlan),
          ),
        ]),
      );
    }
    final s = _start!;
    final done = _days.toSet();
    final todayRoutine = day < 28 ? wallPilatesDay(day) : null;
    return Column(children: [
      if (day >= 28)
        AppInfoCard(L(t, 'wp_plan_done'), icon: Icons.emoji_events_rounded)
      else if (todayRoutine == null)
        AppInfoCard('${Lf(t, 'wp_day', {'n': day + 1})} · ${L(t, 'wp_rest_day')}', icon: Icons.weekend_rounded)
      else
        _card(todayRoutine, title: '${Lf(t, 'wp_day', {'n': day + 1})} · ${L(t, todayRoutine.key)}'),
      AppPanel(
        child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < 28; i++) _dot(DateTime(s.year, s.month, s.day + i), i, i == day, done),
        ]),
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(onPressed: _startPlan, icon: const Icon(Icons.restart_alt_rounded), label: Text(L(t, 'wp_plan_restart'))),
      ),
    ]);
  }

  Widget _dot(DateTime date, int i, bool isToday, Set<String> done) {
    final rest = kWallPilatesPlan[i] == null;
    final ok = done.contains(isoDay(date));
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ok ? AppLook.of(context).accent : Colors.white.withValues(alpha: rest ? 0.04 : 0.1),
        border: isToday ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: ok
          ? const Icon(Icons.check_rounded, size: 20, color: Colors.black87)
          : rest
              ? const Icon(Icons.bedtime_outlined, size: 16, color: Colors.white54)
              : Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _active;
    if (a != null) {
      return ToolList(children: [RoutinePlayer(tool: t, routine: a, onDone: _done)]);
    }
    return ToolList(children: [
      AppInfoCard(L(t, 'wp_safety'), icon: Icons.health_and_safety_rounded),
      if (_justDone) AppInfoCard(L(t, 'well_done'), icon: Icons.emoji_events_rounded),
      AppPanel(
        child: Row(children: [
          Expanded(child: AppResult(label: L(t, 'streak'), value: '${streak(_days, DateTime.now())}', lang: t.lang)),
          Expanded(child: AppResult(label: L(t, 'sessions'), value: '${_days.length}', lang: t.lang)),
        ]),
      ),
      AppHeading(L(t, 'wp_plan'), icon: Icons.calendar_month_rounded),
      _plan(),
      AppHeading(L(t, 'wp_routines'), icon: Icons.self_improvement_rounded),
      for (final r in kWallPilates.where((r) => !r.extra)) _card(r),
      for (final r in kWallPilates.where((r) => r.extra)) ExtraGate(tool: t, feature: 'routine_${r.key}', child: _card(r)),
      AppHeading(L(t, 'wp_moves'), icon: Icons.menu_book_rounded),
      for (final e in _moves)
        Card(
          child: Column(children: [
            ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: CustomPaint(painter: FigurePainter(e.a, null, 0, AppLook.of(context).accent, wall: e.wall)),
              ),
              title: Text(L(t, 'ex_${e.key}'), style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: Icon(_openEx == e.key ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              onTap: () => setState(() => _openEx = _openEx == e.key ? null : e.key),
            ),
            if (_openEx == e.key) ...[
              Figure(e, height: 180),
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(L(t, 'tip_${e.key}'))),
            ],
          ]),
        ),
      AppInfoCard(L(t, 'exercise_hint'), icon: Icons.favorite_border_rounded),
    ]);
  }
}

/// 30 gün meydan okumaları: kademeli artan tekrar/saniye hedefleri, her 4.
/// gün dinlenme, üç seviye, günlük işaretleme ve 30 günlük ızgara. Bir gün
/// en fazla bir adım ilerlenir; kaçırılan gün planı bozmaz.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../data.dart';
import '../logic.dart';

class ChallengeTool extends StatefulWidget {
  final ToolContext t;
  const ChallengeTool(this.t, {super.key});

  @override
  State<ChallengeTool> createState() => _ChallengeToolState();
}

class _ChallengeToolState extends State<ChallengeTool> {
  /// Meydan okuma anahtarı → {level, done: [gün], days: [iso tarih]}.
  Map<String, Map<String, Object?>> _st = {};
  String? _open;
  bool _loaded = false;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('state').then((m) {
      if (!mounted) return;
      setState(() {
        _st = {for (final e in m.entries) if (e.value is Map) e.key: (e.value as Map).cast<String, Object?>()};
        _loaded = true;
      });
    });
  }

  Future<void> _save() => t.store.writeMap('state', _st);

  List<int> _done(String k) => [for (final d in (_st[k]?['done'] as List? ?? const [])) (d as num).toInt()];
  List<String> _days(String k) => [for (final d in (_st[k]?['days'] as List? ?? const [])) '$d'];
  int _level(String k) => ((_st[k]?['level'] as num?) ?? 1).toInt();

  /// Sıradaki gün (1–30, bittiyse 31).
  int _next(String k) {
    final done = _done(k).toSet();
    for (var d = 1; d <= kChallengeDays; d++) {
      if (!done.contains(d)) return d;
    }
    return kChallengeDays + 1;
  }

  bool _doneToday(String k) => _days(k).contains(isoDay(DateTime.now()));

  Future<void> _complete(Challenge c) async {
    final k = c.key;
    final day = _next(k);
    if (day > kChallengeDays || _doneToday(k)) return;
    final st = _st.putIfAbsent(k, () => {'level': 1});
    st['done'] = [..._done(k), day];
    st['days'] = [..._days(k), isoDay(DateTime.now())];
    setState(() {});
    await _save();
  }

  Future<void> _start(Challenge c, int level) async {
    setState(() => _st[c.key] = {'level': level, 'done': <int>[], 'days': <String>[], 'start': isoDay(DateTime.now())});
    await _save();
  }

  Future<void> _reset(Challenge c) async {
    if (!await confirm(context, t, L(t, 'reset_q'))) return;
    setState(() => _st.remove(c.key));
    await _save();
  }

  String _unit(Challenge c, int v) => c.secs ? '$v ${L(t, 'seconds')}' : '$v ${L(t, 'reps')}';

  Widget _detail(Challenge c) {
    final s = AppLook.of(context);
    final level = _level(c.key);
    final started = _st.containsKey(c.key);
    final next = _next(c.key);
    final done = _done(c.key).toSet();
    final finished = next > kChallengeDays;
    final today = _doneToday(c.key);
    final levels = Ls(t, 'levels');
    return ToolList(children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() => _open = null),
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(L(t, 'back')),
        ),
      ),
      AppPanel(
        child: Column(children: [
          Text(L(t, c.key), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Figure(exercise(c.exercise), height: 170),
          Text(L(t, 'ex_${c.exercise}'), style: const TextStyle(color: Colors.white70)),
        ]),
      ),
      if (!started) ...[
        AppPanel(
          child: Column(children: [
            for (var lv = 0; lv < 3; lv++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.signal_cellular_alt_rounded, color: [Colors.greenAccent, Colors.amber, Colors.redAccent][lv]),
                title: Text(lv < levels.length ? levels[lv] : '$lv'),
                subtitle: Text('${L(t, 'day')} 1: ${_unit(c, challengeTarget(c, 1, lv))} → '
                    '${L(t, 'day')} 30: ${_unit(c, challengeTarget(c, 30, lv))}'),
                trailing: FilledButton(onPressed: () => _start(c, lv), child: Text(L(t, 'start'))),
              ),
          ]),
        ),
        WarnCard(L(t, 'exercise_hint')),
      ] else ...[
        if (finished)
          AppPanel(
            child: Column(children: [
              const Icon(Icons.emoji_events_rounded, size: 56, color: Colors.amber),
              Text(L(t, 'well_done'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text('${L(t, 'total')}: ${_unit(c, challengeTotal(c, level))}'),
            ]),
          )
        else
          BigReadout(
            challengeRest(next) ? '—' : '${challengeTarget(c, next, level)}',
            unit: challengeRest(next) ? '' : (c.secs ? 's' : '×'),
            caption: '${L(t, 'day')} $next · ${challengeRest(next) ? L(t, 'rest') : L(t, 'ex_${c.exercise}')}',
          ),
        if (!finished)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppButton(
              label: today ? L(t, 'come_back') : (challengeRest(next) ? L(t, 'rest_done') : L(t, 'i_did_it')),
              icon: today ? Icons.schedule_rounded : Icons.check_circle_rounded,
              onPressed: today ? null : () => _complete(c),
            ),
          ),
        AppPanel(
          child: GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var d = 1; d <= kChallengeDays; d++)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: done.contains(d)
                        ? s.accent.withValues(alpha: 0.85)
                        : d == next
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.06),
                    border: d == next ? Border.all(color: s.accent, width: 2) : null,
                  ),
                  alignment: Alignment.center,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$d', style: TextStyle(fontWeight: FontWeight.w900, color: done.contains(d) ? Colors.black : Colors.white)),
                    Text(
                      challengeRest(d) ? '☾' : '${challengeTarget(c, d, level)}',
                      style: TextStyle(fontSize: 10, color: done.contains(d) ? Colors.black87 : Colors.white60),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'level'), value: level < levels.length ? levels[level] : '$level', lang: t.lang),
            AppResult(label: L(t, 'progress'), value: '${done.length}/$kChallengeDays', lang: t.lang),
            AppResult(label: L(t, 'streak'), value: '${streak(_days(c.key), DateTime.now())} ${L(t, 'days')}', lang: t.lang),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => _reset(c),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(L(t, 'reset')),
          ),
        ),
        WarnCard(L(t, 'exercise_hint')),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final open = _open == null ? null : kChallenges.where((c) => c.key == _open).firstOrNull;
    if (open != null) return _detail(open);
    final s = AppLook.of(context);
    return ToolList(children: [
      AppInfoCard(L(t, 'challenge_intro'), icon: Icons.emoji_events_rounded),
      for (final c in kChallenges)
        Builder(builder: (_) {
          final started = _st.containsKey(c.key);
          final n = _done(c.key).length;
          final next = _next(c.key);
          return AppPanel(
            padding: const EdgeInsets.all(8),
            child: ListTile(
              onTap: () => setState(() => _open = c.key),
              leading: SizedBox(
                width: 56,
                height: 56,
                child: CustomPaint(painter: FigurePainter(exercise(c.exercise).a, null, 0, s.accent)),
              ),
              title: Text(L(t, c.key), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: started
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: n / kChallengeDays, color: s.accent),
                      const SizedBox(height: 4),
                      Text(next > kChallengeDays
                          ? L(t, 'well_done')
                          : '${L(t, 'day')} $next · ${challengeRest(next) ? L(t, 'rest') : _unit(c, challengeTarget(c, next, _level(c.key)))}'),
                    ])
                  : Text('${_unit(c, challengeTarget(c, 1, 1))} → ${_unit(c, challengeTarget(c, 30, 1))}'),
              trailing: _doneToday(c.key) ? const Icon(Icons.check_circle_rounded, color: Colors.greenAccent) : const Icon(Icons.chevron_right_rounded),
            ),
          );
        }),
    ]);
  }
}

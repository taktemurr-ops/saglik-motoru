/// Spor yardımcıları: satranç saati ve turnuva fikstürü.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../logic.dart';

// ------------------------------------------------------------- satranç

class ChessClockTool extends StatefulWidget {
  final ToolContext t;
  const ChessClockTool(this.t, {super.key});

  @override
  State<ChessClockTool> createState() => _ChessClockToolState();
}

class _ChessClockToolState extends State<ChessClockTool> {
  int _base = 5, _inc = 3;
  bool _delay = false;
  ChessClock? _clock;
  Timer? _tick;
  final TonePlayer _beep = TonePlayer();

  ToolContext get t => widget.t;
  int get _now => DateTime.now().millisecondsSinceEpoch;

  static const _presets = [(1, 0), (3, 2), (5, 0), (5, 3), (10, 0), (10, 5), (15, 10), (30, 0)];

  @override
  void initState() {
    super.initState();
    t.store.readMap('cfg').then((m) {
      if (!mounted) return;
      setState(() {
        _base = (m['base'] as num?)?.toInt() ?? _base;
        _inc = (m['inc'] as num?)?.toInt() ?? _inc;
        _delay = m['delay'] == true;
      });
    });
  }

  void _new() {
    t.store.writeMap('cfg', {'base': _base, 'inc': _inc, 'delay': _delay});
    setState(() => _clock = ChessClock(baseMs: _base * 60000, incMs: _delay ? 0 : _inc * 1000, delayMs: _delay ? _inc * 1000 : 0));
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final c = _clock;
      if (c == null || !mounted) return;
      final was = c.flagged;
      c.check(_now);
      if (was == null && c.flagged != null) {
        unawaited(_beep.play(beepLong));
        HapticFeedback.heavyImpact();
      }
      setState(() {});
    });
  }

  void _press(int p) {
    final c = _clock;
    if (c == null) return;
    c.press(p, _now);
    HapticFeedback.selectionClick();
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _beep.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  String _fmt(int ms) {
    final s = (ms / 1000).ceil();
    if (ms < 10000) return (ms / 1000).toStringAsFixed(1);
    return clock(s);
  }

  @override
  Widget build(BuildContext context) {
    final c = _clock;
    if (c == null) {
      return ToolList(children: [
        Section(L(t, 'presets'), icon: Icons.bolt_rounded, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _presets)
              ChoiceChip(
                label: Text('${p.$1} + ${p.$2}'),
                selected: _base == p.$1 && _inc == p.$2,
                onSelected: (_) => setState(() {
                  _base = p.$1;
                  _inc = p.$2;
                }),
              ),
          ]),
        ]),
        Section(L(t, 'settings'), icon: Icons.tune_rounded, children: [
          SliderRow(label: L(t, 'minutes'), value: _base.toDouble(), min: 1, max: 90, divisions: 89,
              text: (v) => '${v.round()}', onChanged: (v) => setState(() => _base = v.round())),
          SliderRow(label: L(t, 'seconds'), value: _inc.toDouble(), min: 0, max: 60, divisions: 60,
              text: (v) => '+${v.round()}', onChanged: (v) => setState(() => _inc = v.round())),
          Choice<bool>(values: const [false, true], labels: [L(t, 'increment'), L(t, 'delay')], selected: _delay,
              onChanged: (v) => setState(() => _delay = v)),
        ]),
        Center(child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _new)),
        AppInfoCard(L(t, 'chess_hint'), icon: Icons.info_outline_rounded),
      ]);
    }
    final now = _now;
    Widget side(int p) {
      final active = c.active == p;
      final flagged = c.flagged == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => _press(p),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: flagged ? Colors.red.shade700 : (active ? AppLook.of(context).accent : Colors.white10),
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: RotatedBox(
              quarterTurns: p == 0 ? 2 : 0,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_fmt(c.remaining(p, now)),
                    style: TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: active ? Colors.black : Colors.white)),
                Text('${L(t, 'moves')}: ${c.moves[p]}', style: TextStyle(color: active ? Colors.black87 : Colors.white70)),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      side(0),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: L(t, 'pause'),
          icon: const Icon(Icons.pause_rounded),
          onPressed: () => setState(() => c.pause(_now)),
        ),
        IconButton(
          tooltip: L(t, 'reset'),
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: () async {
            if (c.flagged == null && c.active != null && !await confirm(context, t, L(t, 'reset_q'))) return;
            _tick?.cancel();
            unawaited(WakelockPlus.disable().catchError((Object _) {}));
            setState(() => _clock = null);
          },
        ),
      ]),
      side(1),
    ]);
  }
}

// ------------------------------------------------------------- turnuva

class TournamentTool extends StatefulWidget {
  final ToolContext t;
  const TournamentTool(this.t, {super.key});

  @override
  State<TournamentTool> createState() => _TournamentToolState();
}

class _TournamentToolState extends State<TournamentTool> {
  List<String> _names = [];
  bool _knockout = false;
  bool _started = false;

  /// Lig sonuçları: "tur|ev|dep" → [ev gol, dep gol].
  Map<String, Object?> _scores = {};

  /// Eleme: her turun kazanan dizini listesi.
  List<List<int>> _winners = [];
  final _names0 = TextEditingController();

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('state').then((m) {
      if (!mounted) return;
      setState(() {
        _names = [for (final n in (m['names'] as List?) ?? const []) '$n'];
        _knockout = m['ko'] == true;
        _started = m['started'] == true;
        _scores = Map<String, Object?>.from((m['scores'] as Map?) ?? const {});
        _winners = [
          for (final r in (m['winners'] as List?) ?? const []) [for (final x in r as List) (x as num).toInt()],
        ];
        _names0.text = _names.join('\n');
      });
    });
  }

  Future<void> _save() => t.store.writeMap('state', {
        'names': _names,
        'ko': _knockout,
        'started': _started,
        'scores': _scores,
        'winners': _winners,
      });

  void _start() {
    final names = _names0.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    if (names.length < 2 || names.length > 64) return;
    setState(() {
      _names = names;
      _started = true;
      _scores = {};
      _winners = [];
    });
    _save();
  }

  Future<void> _score(int r, int a, int b) async {
    final key = '$r|$a|$b';
    final cur = (_scores[key] as List?) ?? const [];
    final ca = TextEditingController(text: cur.isEmpty ? '' : '${cur[0]}');
    final cb = TextEditingController(text: cur.isEmpty ? '' : '${cur[1]}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_names[a]} – ${_names[b]}'),
        content: Row(children: [
          Expanded(child: AppNumberField(controller: ca, label: _names[a])),
          const SizedBox(width: 8),
          Expanded(child: AppNumberField(controller: cb, label: _names[b])),
        ]),
        actions: [
          if (cur.isNotEmpty) TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L(t, 'clear'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(L(t, 'save'))),
        ],
      ),
    );
    final x = numOf(ca)?.round(), y = numOf(cb)?.round();
    ca.dispose();
    cb.dispose();
    if (ok == false) {
      setState(() => _scores.remove(key));
    } else if (ok == true && x != null && y != null && x >= 0 && y >= 0) {
      setState(() => _scores[key] = [x, y]);
    } else {
      return;
    }
    await _save();
  }

  /// Eleme turundaki eşleşmeler (dizinler; -1 bay).
  List<(int, int)> _koRound(int r) {
    if (r == 0) return knockoutFirstRound(_names.length);
    final prev = _winners[r - 1];
    return [for (var i = 0; i + 1 < prev.length; i += 2) (prev[i], prev[i + 1])];
  }

  void _pickWinner(int r, int game, int who) {
    final games = _koRound(r);
    setState(() {
      while (_winners.length <= r) {
        _winners.add(List<int>.filled(games.length, -2));
      }
      _winners[r][game] = who;
      // Sonraki turlar artık geçersiz olabilir.
      _winners = _winners.sublist(0, r + 1);
    });
    _save();
  }

  @override
  void dispose() {
    _names0.dispose();
    super.dispose();
  }

  Widget _league() {
    final n = _names.length;
    final rounds = roundRobin(n);
    final res = <(int, int, int, int)>[];
    _scores.forEach((k, v) {
      final p = k.split('|');
      final l = v as List?;
      if (p.length == 3 && l != null && l.length == 2) {
        res.add((int.parse(p[1]), int.parse(p[2]), (l[0] as num).toInt(), (l[1] as num).toInt()));
      }
    });
    final table = standings(n, res);
    return Column(children: [
      Section(L(t, 'standings'), icon: Icons.leaderboard_rounded, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 14,
            columns: [
              const DataColumn(label: Text('#')),
              DataColumn(label: Text(L(t, 'name'))),
              DataColumn(label: Text(L(t, 'played_s')), numeric: true),
              DataColumn(label: Text(L(t, 'won_s')), numeric: true),
              DataColumn(label: Text(L(t, 'drawn_s')), numeric: true),
              DataColumn(label: Text(L(t, 'lost_s')), numeric: true),
              const DataColumn(label: Text('±'), numeric: true),
              DataColumn(label: Text(L(t, 'points_s')), numeric: true),
            ],
            rows: [
              for (var i = 0; i < table.length; i++)
                DataRow(cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(Text(_names[table[i].team])),
                  DataCell(Text('${table[i].played}')),
                  DataCell(Text('${table[i].won}')),
                  DataCell(Text('${table[i].drawn}')),
                  DataCell(Text('${table[i].lost}')),
                  DataCell(Text('${table[i].diff}')),
                  DataCell(Text('${table[i].points}', style: const TextStyle(fontWeight: FontWeight.w900))),
                ]),
            ],
          ),
        ),
      ]),
      for (var r = 0; r < rounds.length; r++)
        Section(Lf(t, 'round_n', {'n': r + 1}), children: [
          for (final g in rounds[r])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${_names[g.$1]}  –  ${_names[g.$2]}'),
              trailing: Text(() {
                final s = _scores['$r|${g.$1}|${g.$2}'] as List?;
                return s == null ? '–' : '${s[0]} : ${s[1]}';
              }(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              onTap: () => _score(r, g.$1, g.$2),
            ),
          if (n.isOdd)
            Text(Lf(t, 'bye_x', {'name': _names[_byeOf(rounds[r], n)]}), style: const TextStyle(color: Colors.white60)),
        ]),
    ]);
  }

  int _byeOf(List<(int, int)> games, int n) {
    final playing = {for (final g in games) ...[g.$1, g.$2]};
    for (var i = 0; i < n; i++) {
      if (!playing.contains(i)) return i;
    }
    return 0;
  }

  Widget _bracket() {
    final out = <Widget>[];
    for (var r = 0;; r++) {
      final games = _koRound(r);
      if (games.isEmpty) break;
      // İlk turdaki "bay" maçları otomatik geçer.
      if (r < _winners.length || r == 0) {
        while (_winners.length <= r) {
          _winners.add(List<int>.filled(games.length, -2));
        }
        for (var i = 0; i < games.length; i++) {
          if (games[i].$2 == -1 && _winners[r][i] == -2) _winners[r][i] = games[i].$1;
        }
      }
      out.add(Section(games.length == 1 ? L(t, 'final') : Lf(t, 'round_n', {'n': r + 1}), children: [
        for (var i = 0; i < games.length; i++)
          Row(children: [
            for (final who in [games[i].$1, games[i].$2])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: who == -1
                      ? Text(L(t, 'bye'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38))
                      : ChoiceChip(
                          label: Text(_names[who], overflow: TextOverflow.ellipsis),
                          selected: r < _winners.length && _winners[r][i] == who,
                          onSelected: (_) => _pickWinner(r, i, who),
                        ),
                ),
              ),
          ]),
      ]));
      final done = r < _winners.length && !_winners[r].contains(-2);
      if (!done) break;
      if (games.length == 1) {
        out.insert(0, AppPanel(
          child: Row(children: [
            const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Text('${L(t, 'winner')}: ${_names[_winners[r][0]]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          ]),
        ));
        break;
      }
    }
    return Column(children: out);
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return ToolList(children: [
        Choice<bool>(values: const [false, true], labels: [L(t, 'league'), L(t, 'knockout')], selected: _knockout,
            onChanged: (v) => setState(() => _knockout = v)),
        AppPanel(child: AppTextField(controller: _names0, label: L(t, 'participants_hint'), maxLines: 10)),
        Center(child: AppButton(label: L(t, 'generate'), icon: Icons.account_tree_rounded, onPressed: _start)),
      ]);
    }
    return ToolList(children: [
      _knockout ? _bracket() : _league(),
      Center(
        child: TextButton.icon(
          icon: const Icon(Icons.restart_alt_rounded),
          label: Text(L(t, 'new_tournament')),
          onPressed: () async {
            if (!await confirm(context, t, L(t, 'reset_q'))) return;
            setState(() => _started = false);
            await _save();
          },
        ),
      ),
    ]);
  }
}

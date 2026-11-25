/// Kayıt ve kontrol araçları: tansiyon/şeker günlüğü, ilaç hatırlatıcı,
/// duruş hatırlatıcı, görme ve renk testi, işitme testi, kamera ile nabız
/// tahmini. Hiçbiri tıbbi ölçüm, tanı ya da dozaj önerisi değildir.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../data.dart';
import '../logic.dart';
import '../platform/notify.dart';

// -------------------------------------------------------- tansiyon / şeker

class BpSugarTool extends StatefulWidget {
  final ToolContext t;
  const BpSugarTool(this.t, {super.key});

  @override
  State<BpSugarTool> createState() => _BpSugarToolState();
}

class _BpSugarToolState extends State<BpSugarTool> {
  bool _sugar = false;
  bool _mmol = false;
  List<Map<String, Object?>> _e = [];
  Map<String, Object?> _range = {};
  final _a = TextEditingController(), _b = TextEditingController(), _c = TextEditingController(), _note = TextEditingController();
  final _r1 = TextEditingController(), _r2 = TextEditingController(), _r3 = TextEditingController(), _r4 = TextEditingController();

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _e = await t.store.readList('entries');
    _range = await t.store.readMap('range');
    _mmol = _range['mmol'] == true;
    _fillRange();
    if (mounted) setState(() {});
  }

  double? _rv(String k) => (_range[k] as num?)?.toDouble();

  void _fillRange() {
    String s(String k) => _rv(k) == null ? '' : fmt(_sugarShow(_rv(k)!, k.startsWith('g')), 1);
    _r1.text = s('sys');
    _r2.text = s('dia');
    _r3.text = s('glo');
    _r4.text = s('ghi');
  }

  double _sugarShow(double mgdl, bool isSugar) => isSugar && _mmol ? mgdlToMmol(mgdl) : mgdl;
  double _sugarIn(double v) => _mmol ? mmolToMgdl(v) : v;
  String get _su => _mmol ? 'mmol/L' : 'mg/dL';

  Future<void> _add() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, Object?> e;
    if (_sugar) {
      final v = numOf(_a);
      if (v == null) return;
      final mg = _sugarIn(v);
      if (mg < 10 || mg > 1000) return;
      e = {'at': now, 'type': 'sugar', 'v': mg, 'note': _note.text.trim()};
    } else {
      final s = numOf(_a), d = numOf(_b), p = numOf(_c);
      if (s == null || d == null || s < 40 || s > 300 || d < 20 || d > 200) return;
      e = {'at': now, 'type': 'bp', 'sys': s, 'dia': d, if (p != null) 'pulse': p, 'note': _note.text.trim()};
    }
    setState(() {
      _e = <Map<String, Object?>>[..._e, e];
      if (_e.length > 3000) _e = _e.sublist(_e.length - 3000);
      for (final c in [_a, _b, _c, _note]) {
        c.clear();
      }
    });
    await t.store.writeList('entries', _e);
  }

  Future<void> _saveRange() async {
    double? v(TextEditingController c, bool sugar) {
      final x = numOf(c);
      return x == null ? null : (sugar ? _sugarIn(x) : x);
    }

    _range = {
      'mmol': _mmol,
      if (v(_r1, false) != null) 'sys': v(_r1, false),
      if (v(_r2, false) != null) 'dia': v(_r2, false),
      if (v(_r3, true) != null) 'glo': v(_r3, true),
      if (v(_r4, true) != null) 'ghi': v(_r4, true),
    };
    await t.store.writeMap('range', _range);
    if (mounted) setState(() {});
  }

  bool _outside(Map<String, Object?> e) {
    if (e['type'] == 'sugar') return !inRange(((e['v'] as num?) ?? 0).toDouble(), _rv('glo'), _rv('ghi'));
    return !inRange(((e['sys'] as num?) ?? 0).toDouble(), null, _rv('sys')) ||
        !inRange(((e['dia'] as num?) ?? 0).toDouble(), null, _rv('dia'));
  }

  String _csv() {
    final rows = [
      csvRow(['time', 'type', 'systolic', 'diastolic', 'pulse', 'glucose_mg_dl', 'note']),
      for (final e in _e)
        csvRow([
          DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt()).toIso8601String().substring(0, 16),
          e['type'], e['sys'], e['dia'], e['pulse'], e['v'], e['note'],
        ]),
    ];
    return rows.join('\n');
  }

  @override
  void dispose() {
    for (final c in [_a, _b, _c, _note, _r1, _r2, _r3, _r4]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final list = [for (final e in _e) if ((e['type'] == 'sugar') == _sugar) e];
    final cut = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final month = [for (final e in list) if (((e['at'] as num?) ?? 0) >= cut) e];
    double avg(String k) => month.isEmpty ? 0 : month.fold(0.0, (a, e) => a + ((e[k] as num?) ?? 0).toDouble()) / month.length;
    return ToolList(children: [
      Choice<bool>(values: const [false, true], labels: [L(t, 'bp'), L(t, 'sugar')], selected: _sugar, onChanged: (v) => setState(() => _sugar = v)),
      if (_sugar)
        Choice<bool>(values: const [false, true], labels: const ['mg/dL', 'mmol/L'], selected: _mmol, onChanged: (v) {
          setState(() => _mmol = v);
          _fillRange();
          _saveRange();
        }),
      Section(L(t, 'add_entry'), icon: Icons.add_rounded, children: [
        if (_sugar)
          AppNumberField(controller: _a, label: L(t, 'glucose'), suffix: _su, decimal: true)
        else ...[
          Row(children: [
            Expanded(child: AppNumberField(controller: _a, label: L(t, 'systolic'), suffix: 'mmHg')),
            const SizedBox(width: 8),
            Expanded(child: AppNumberField(controller: _b, label: L(t, 'diastolic'), suffix: 'mmHg')),
          ]),
          AppNumberField(controller: _c, label: L(t, 'pulse'), suffix: '/min'),
        ],
        AppTextField(controller: _note, label: L(t, 'note')),
        Center(child: AppButton(label: L(t, 'save'), icon: Icons.check_rounded, onPressed: _add)),
      ]),
      if (month.isNotEmpty)
        AppPanel(
          child: Column(children: [
            Text(L(t, 'last_30'), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (_sugar)
              AppResult(label: L(t, 'average'), value: '${fmt(_sugarShow(avg('v'), true))} $_su', lang: t.lang)
            else
              AppResult(label: L(t, 'average'), value: '${fmt(avg('sys'), 0)}/${fmt(avg('dia'), 0)} mmHg', lang: t.lang),
            AppResult(label: L(t, 'count'), value: '${month.length}', lang: t.lang),
            if (month.length >= 2)
              Sparkline([for (final e in month) _sugar ? _sugarShow(((e['v'] as num?) ?? 0).toDouble(), true) : ((e['sys'] as num?) ?? 0).toDouble()]),
          ]),
        ),
      if (list.isNotEmpty)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final e in list.reversed.take(30))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: _outside(e) ? Tooltip(message: L(t, 'outside_range'), child: const Icon(Icons.flag_rounded, color: Colors.amber)) : const Icon(Icons.circle_outlined, size: 14),
              title: Text(_sugar
                  ? '${fmt(_sugarShow(((e['v'] as num?) ?? 0).toDouble(), true))} $_su'
                  : '${fmt((e['sys'] as num?) ?? 0, 0)}/${fmt((e['dia'] as num?) ?? 0, 0)}${e['pulse'] == null ? '' : '  ·  ${fmt(e['pulse'] as num, 0)} /min'}'),
              subtitle: Text([
                loc.formatShortDate(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt())),
                loc.formatTimeOfDay(TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt()))),
                if ('${e['note'] ?? ''}'.isNotEmpty) '${e['note']}',
              ].join(' · ')),
              trailing: IconButton(
                tooltip: L(t, 'delete'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  if (!await confirm(context, t, L(t, 'delete_q'))) return;
                  setState(() => _e = [for (final x in _e) if (!identical(x, e)) x]);
                  await t.store.writeList('entries', _e);
                },
              ),
            ),
        ]),
      Section(L(t, 'my_range'), icon: Icons.tune_rounded, children: [
        Text(L(t, 'my_range_hint'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
        if (_sugar)
          Row(children: [
            Expanded(child: AppNumberField(controller: _r3, label: L(t, 'minimum'), suffix: _su, decimal: true)),
            const SizedBox(width: 8),
            Expanded(child: AppNumberField(controller: _r4, label: L(t, 'maximum'), suffix: _su, decimal: true)),
          ])
        else
          Row(children: [
            Expanded(child: AppNumberField(controller: _r1, label: '${L(t, 'systolic')} ≤', suffix: 'mmHg')),
            const SizedBox(width: 8),
            Expanded(child: AppNumberField(controller: _r2, label: '${L(t, 'diastolic')} ≤', suffix: 'mmHg')),
          ]),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _saveRange, child: Text(L(t, 'save')))),
      ]),
      if (_e.isNotEmpty)
        ExtraGate(
          tool: t,
          feature: 'csv',
          child: Center(
            child: TextButton.icon(
              icon: const Icon(Icons.copy_all_rounded),
              label: Text(L(t, 'copy_csv')),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _csv()));
                if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'copied'))));
              },
            ),
          ),
        ),
      WarnCard(L(t, 'log_note')),
    ]);
  }
}

// ---------------------------------------------------------------- ilaç

class MedsTool extends StatefulWidget {
  final ToolContext t;
  const MedsTool(this.t, {super.key});

  @override
  State<MedsTool> createState() => _MedsToolState();
}

class _MedsToolState extends State<MedsTool> {
  static const int _base = 35000;
  List<Map<String, Object?>> _meds = [];
  Map<String, Object?> _log = {};

  ToolContext get t => widget.t;
  String get _today => isoDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _meds = await t.store.readList('meds');
    _log = await t.store.readMap('log');
    if (mounted) setState(() {});
    await _schedule();
  }

  List<int> _times(Map<String, Object?> m) => [for (final x in (m['times'] as List?) ?? const []) (x as num).toInt()]..sort();

  /// Her ilaç için önümüzdeki 3 günün hatırlatmaları (uygulama açıldıkça yenilenir).
  Future<void> _schedule() async {
    if (!Notify.supported) return;
    for (var i = 0; i < 40; i++) {
      await cancelDaily(_base + i * 100, slots: 8);
    }
    for (final m in _meds) {
      final id = ((m['id'] as num?) ?? 0).toInt();
      if (m['on'] == false) continue;
      await scheduleDaily(
        base: _base + id * 100,
        minutes: _times(m),
        title: '💊 ${m['name']}',
        body: Lf(t, 'n_med_body', {'name': '${m['name']}', 'dose': '${m['dose'] ?? ''}'}),
        slots: 8,
      );
    }
  }

  Future<void> _save() async {
    await t.store.writeList('meds', _meds);
    await _schedule();
    if (mounted) setState(() {});
  }

  Future<void> _edit([Map<String, Object?>? m]) async {
    await askNotifyOnce(context, t);
    if (!mounted) return;
    final name = TextEditingController(text: '${m?['name'] ?? ''}');
    final dose = TextEditingController(text: '${m?['dose'] ?? ''}');
    var times = m == null ? <int>[8 * 60] : _times(m);
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(L(t, m == null ? 'add_med' : 'edit')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppTextField(controller: name, label: L(t, 'med_name')),
              AppTextField(controller: dose, label: L(t, 'dose_note')),
              for (var i = 0; i < times.length; i++)
                Row(children: [
                  Expanded(
                    child: TimeRow(
                      label: '${L(t, 'time')} ${i + 1}',
                      minute: times[i],
                      onChanged: (v) => setD(() => times = [...times]..[i] = v),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: times.length > 1 ? () => setD(() => times = [...times]..removeAt(i)) : null,
                  ),
                ]),
              if (times.length < 8)
                TextButton.icon(
                  icon: const Icon(Icons.add_alarm_rounded),
                  label: Text(L(t, 'add_time')),
                  onPressed: () => setD(() => times = [...times, 12 * 60]),
                ),
            ]),
          ),
          actions: [
            if (m != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(L(t, 'delete'), style: const TextStyle(color: Colors.redAccent)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L(t, 'cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(L(t, 'save'))),
          ],
        ),
      ),
    );
    if (r == true && name.text.trim().isNotEmpty) {
      final used = {for (final x in _meds) ((x['id'] as num?) ?? 0).toInt()};
      var id = ((m?['id'] as num?) ?? -1).toInt();
      if (id < 0) {
        id = 0;
        while (used.contains(id)) {
          id++;
        }
      }
      if (id < 40) {
        final n = {'id': id, 'name': name.text.trim(), 'dose': dose.text.trim(), 'times': times.toSet().toList()..sort(), 'on': true};
        _meds = <Map<String, Object?>>[for (final x in _meds) if (x['id'] != id) x, n];
        await _save();
      }
    } else if (r == false && m != null) {
      if (mounted && await confirm(context, t, L(t, 'delete_q'))) {
        _meds = [for (final x in _meds) if (x['id'] != m['id']) x];
        await _save();
      }
    }
    name.dispose();
    dose.dispose();
  }

  Future<void> _mark(String key, String v) async {
    setState(() {
      if (_log[key] == v) {
        _log.remove(key);
      } else {
        _log[key] = v;
      }
    });
    final cut = isoDay(DateTime.now().subtract(const Duration(days: 60)));
    _log.removeWhere((k, _) => k.substring(0, 10).compareTo(cut) < 0);
    await t.store.writeMap('log', _log);
  }

  @override
  Widget build(BuildContext context) {
    final slots = <(Map<String, Object?>, int)>[
      for (final m in _meds)
        for (final tm in _times(m)) (m, tm),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return ToolList(children: [
      if (!Notify.supported) notAvailable(t),
      if (_meds.isEmpty) AppInfoCard(L(t, 'med_empty'), icon: Icons.medication_rounded),
      if (slots.isNotEmpty)
        Section(L(t, 'today'), icon: Icons.today_rounded, children: [
          for (final s in slots)
            Builder(builder: (_) {
              final key = '$_today|${s.$1['id']}|${s.$2}';
              final st = _log[key];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(hm(s.$2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                title: Text('${s.$1['name']}'),
                subtitle: '${s.$1['dose'] ?? ''}'.isEmpty ? null : Text('${s.$1['dose']}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: L(t, 'taken'),
                    icon: Icon(Icons.check_circle_rounded, color: st == 't' ? Colors.greenAccent : Colors.white30),
                    onPressed: () => _mark(key, 't'),
                  ),
                  IconButton(
                    tooltip: L(t, 'skipped'),
                    icon: Icon(Icons.remove_circle_rounded, color: st == 's' ? Colors.orangeAccent : Colors.white30),
                    onPressed: () => _mark(key, 's'),
                  ),
                ]),
              );
            }),
        ]),
      Section(L(t, 'medicines'), icon: Icons.medication_rounded, children: [
        for (final m in _meds)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${m['name']}'),
            subtitle: Text(_times(m).map(hm).join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: m['on'] != false,
                onChanged: (v) {
                  m['on'] = v;
                  _save();
                },
              ),
              IconButton(icon: const Icon(Icons.edit_rounded), tooltip: L(t, 'edit'), onPressed: () => _edit(m)),
            ]),
          ),
        Center(child: AppButton(label: L(t, 'add_med'), icon: Icons.add_rounded, onPressed: () => _edit())),
      ]),
      WarnCard(L(t, 'med_hint')),
      AppInfoCard(L(t, 'med_open_hint'), icon: Icons.notifications_active_rounded),
    ]);
  }
}

// ----------------------------------------------------------------- duruş

class PostureTool extends StatefulWidget {
  final ToolContext t;
  const PostureTool(this.t, {super.key});

  @override
  State<PostureTool> createState() => _PostureToolState();
}

class _PostureToolState extends State<PostureTool> {
  bool _on = false;
  int _from = 9 * 60, _to = 18 * 60, _every = 45;
  Map<String, Object?> _checks = {};
  bool _reset = false;

  ToolContext get t => widget.t;
  String get _today => isoDay(DateTime.now());

  static const Routine _mini = Routine('r_mini', [('shoulder_roll', 15), ('chest_open', 15), ('neck_tilt', 15), ('side_bend', 15)]);

  @override
  void initState() {
    super.initState();
    () async {
      final m = await t.store.readMap('cfg');
      _on = m['on'] == true;
      _from = (m['from'] as num?)?.toInt() ?? _from;
      _to = (m['to'] as num?)?.toInt() ?? _to;
      _every = (m['every'] as num?)?.toInt() ?? _every;
      _checks = await t.store.readMap('checks');
      if (mounted) setState(() {});
    }();
  }

  Future<void> _apply(bool on) async {
    if (on) await askNotifyOnce(context, t);
    setState(() => _on = on);
    await t.store.writeMap('cfg', {'on': on, 'from': _from, 'to': _to, 'every': _every});
    if (on) {
      await scheduleDaily(base: 36000, minutes: reminderSlots(_from, _to, _every), title: L(t, 'n_posture_title'), body: L(t, 'n_posture_body'));
    } else {
      await cancelDaily(36000);
    }
  }

  Future<void> _check() async {
    setState(() => _checks[_today] = ((_checks[_today] as num?) ?? 0).toInt() + 1);
    await t.store.writeMap('checks', _checks);
  }

  @override
  Widget build(BuildContext context) {
    if (_reset) {
      return ToolList(children: [
        RoutinePlayer(
          tool: t,
          routine: _mini,
          onDone: (done) {
            if (done) _check();
            setState(() => _reset = false);
          },
        ),
      ]);
    }
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          BigReadout('${((_checks[_today] as num?) ?? 0).toInt()}', caption: L(t, 'checks_today')),
          Wrap(spacing: 10, alignment: WrapAlignment.center, children: [
            AppButton(label: L(t, 'i_checked'), icon: Icons.accessibility_new_rounded, onPressed: _check),
            AppButton(label: L(t, 'quick_reset'), icon: Icons.self_improvement_rounded, onPressed: () => setState(() => _reset = true)),
          ]),
        ]),
      ),
      Section(L(t, 'posture_tips'), icon: Icons.chair_rounded, children: [
        for (var i = 0; i < 5; i++)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_rounded), title: Text(L(t, 'pt_$i'))),
      ]),
      Section(L(t, 'reminders'), icon: Icons.notifications_rounded, children: [
        if (!Notify.supported) notAvailable(t),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(L(t, 'remind_me')), value: _on, onChanged: Notify.supported ? _apply : null),
        TimeRow(label: L(t, 'from'), minute: _from, onChanged: (v) => setState(() => _from = v)),
        TimeRow(label: L(t, 'to'), minute: _to, onChanged: (v) => setState(() => _to = v)),
        SliderRow(
          label: L(t, 'every'),
          value: _every.toDouble(),
          min: 15,
          max: 120,
          divisions: 21,
          text: (v) => '${v.round()} ${L(t, 'min_short')}',
          onChanged: (v) => setState(() => _every = v.round()),
        ),
        if (_on) TextButton(onPressed: () => _apply(true), child: Text(L(t, 'apply'))),
      ]),
    ]);
  }
}

// ------------------------------------------------------------- görme

class VisionTool extends StatefulWidget {
  final ToolContext t;
  const VisionTool(this.t, {super.key});

  @override
  State<VisionTool> createState() => _VisionToolState();
}

class _VisionToolState extends State<VisionTool> {
  // 0 menü, 1 halka testi, 2 renk testi, 3 sonuç
  int _mode = 0;
  final math.Random _rnd = math.Random();
  int _level = 0, _gap = 0, _miss = 0, _best = -1, _tries = 0;
  int _plate = 0, _right = 0, _digit = 0, _seed = 1;
  String _result = '';

  ToolContext get t => widget.t;

  // Renk çiftleri (rakam, zemin): ilki herkesin görebileceği kontrol levhası,
  // diğerleri kırmızı-yeşil ve mavi-sarı karışıklık eksenlerinde özgün seçimler.
  static const List<(Color, Color, Color, Color)> _palettes = [
    (Color(0xFFE53935), Color(0xFFFF7043), Color(0xFF546E7A), Color(0xFF78909C)),
    (Color(0xFFD4795A), Color(0xFFC98A4B), Color(0xFF9DA552), Color(0xFF8FA05A)),
    (Color(0xFFB8875C), Color(0xFFC07F5E), Color(0xFF93A161), Color(0xFFA0A35C)),
    (Color(0xFFCC7A6E), Color(0xFFD6866A), Color(0xFF8E9E78), Color(0xFF9BA27A)),
    (Color(0xFF7FA35B), Color(0xFF8AAB62), Color(0xFFC1855E), Color(0xFFB88E58)),
    (Color(0xFFA08A4E), Color(0xFFAE8D55), Color(0xFF7C9C6A), Color(0xFF86A06C)),
    (Color(0xFF6E8FCB), Color(0xFF7C99CC), Color(0xFF9AA58A), Color(0xFFA2AE8C)),
    (Color(0xFFB4A84E), Color(0xFFBCAE58), Color(0xFF8E9BB5), Color(0xFF9AA4BE)),
  ];

  void _startRing() => setState(() {
        _mode = 1;
        _level = 0;
        _miss = 0;
        _best = -1;
        _tries = 0;
        _gap = _rnd.nextInt(4);
      });

  void _answerRing(int dir) {
    final ok = dir == _gap;
    setState(() {
      _tries++;
      if (ok) {
        _best = _level;
        _miss = 0;
        if (_tries >= 2 || _level == 0) {
          _level++;
          _tries = 0;
        }
      } else {
        _miss++;
      }
      if (_miss >= 2 || _level >= kRingSizes.length) {
        _result = Lf(t, 'ring_result', {'n': _best + 1, 'm': kRingSizes.length});
        _mode = 3;
      }
      _gap = _rnd.nextInt(4);
    });
  }

  void _startColor() => setState(() {
        _mode = 2;
        _plate = 0;
        _right = 0;
        _newPlate();
      });

  void _newPlate() {
    _digit = 1 + _rnd.nextInt(9);
    _seed = _rnd.nextInt(1 << 30);
  }

  void _answerColor(int? d) {
    setState(() {
      if (d == _digit) _right++;
      _plate++;
      if (_plate >= _palettes.length) {
        _result = Lf(t, 'color_result', {'n': _right, 'm': _palettes.length});
        _mode = 3;
      } else {
        _newPlate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case 1:
        final size = kRingSizes[_level.clamp(0, kRingSizes.length - 1)];
        return ToolList(children: [
          AppInfoCard(L(t, 'distance_hint'), icon: Icons.straighten_rounded),
          AppPanel(
            child: SizedBox(
              height: 240,
              child: CustomPaint(size: Size.infinite, painter: _RingPainter(size, _gap)),
            ),
          ),
          Text(L(t, 'which_gap'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filled(iconSize: 36, onPressed: () => _answerRing(3), icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 8),
            Column(children: [
              IconButton.filled(iconSize: 36, onPressed: () => _answerRing(0), icon: const Icon(Icons.arrow_upward_rounded)),
              const SizedBox(height: 8),
              IconButton.filled(iconSize: 36, onPressed: () => _answerRing(2), icon: const Icon(Icons.arrow_downward_rounded)),
            ]),
            const SizedBox(width: 8),
            IconButton.filled(iconSize: 36, onPressed: () => _answerRing(1), icon: const Icon(Icons.arrow_forward_rounded)),
          ]),
          Center(child: TextButton(onPressed: () => _answerRing(-1), child: Text(L(t, 'cant_see')))),
        ]);
      case 2:
        final p = _palettes[_plate];
        return ToolList(children: [
          AppPanel(
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(painter: _PlatePainter(_digit, _seed, p)),
            ),
          ),
          Text('${L(t, 'which_number')}  (${_plate + 1}/${_palettes.length})', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (var d = 1; d <= 9; d++) SizedBox(width: 64, height: 52, child: FilledButton.tonal(onPressed: () => _answerColor(d), child: Text('$d', style: const TextStyle(fontSize: 22)))),
            SizedBox(height: 52, child: OutlinedButton(onPressed: () => _answerColor(null), child: Text(L(t, 'none_seen')))),
          ]),
        ]);
      case 3:
        return ToolList(children: [
          AppPanel(child: Text(_result, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          WarnCard(L(t, 'vision_note')),
          Center(child: AppButton(label: L(t, 'back'), icon: Icons.arrow_back_rounded, onPressed: () => setState(() => _mode = 0))),
        ]);
    }
    return ToolList(children: [
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppHeading(L(t, 'ring_test'), icon: Icons.radio_button_unchecked_rounded),
          Text(L(t, 'ring_desc')),
          Align(alignment: Alignment.centerRight, child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _startRing)),
        ]),
      ),
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppHeading(L(t, 'color_test'), icon: Icons.palette_rounded),
          Text(L(t, 'color_desc')),
          Align(alignment: Alignment.centerRight, child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _startColor)),
        ]),
      ),
      WarnCard(L(t, 'vision_note')),
    ]);
  }
}

/// Boşluklu halka (0 yukarı, 1 sağ, 2 aşağı, 3 sol).
class _RingPainter extends CustomPainter {
  final double size;
  final int gap;
  _RingPainter(this.size, this.gap);

  @override
  void paint(Canvas canvas, Size s) {
    final r = math.min(s.width, s.height) * 0.42 * size;
    final c = s.center(Offset.zero);
    final w = r * 0.4;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    final mid = [-math.pi / 2, 0.0, math.pi / 2, math.pi][gap];
    const half = 0.42;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - w / 2), mid + half, 2 * math.pi - 2 * half, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.size != size || old.gap != gap;
}

/// Özgün nokta levhası: rakam noktaları ve zemin noktaları iki renk ailesinden.
class _PlatePainter extends CustomPainter {
  final int digit, seed;
  final (Color, Color, Color, Color) pal;
  _PlatePainter(this.digit, this.seed, this.pal);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final rnd = Lcg(seed ^ 0x5bd1e995);
    for (final d in dotPlate(digit, seed)) {
      final pick = rnd.unit() < 0.5;
      final color = d.$4 ? (pick ? pal.$1 : pal.$2) : (pick ? pal.$3 : pal.$4);
      canvas.drawCircle(Offset(d.$1 * s, d.$2 * s), d.$3 * s, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) => old.digit != digit || old.seed != seed;
}

// ------------------------------------------------------------ işitme

class HearingTool extends StatefulWidget {
  final ToolContext t;
  const HearingTool(this.t, {super.key});

  @override
  State<HearingTool> createState() => _HearingToolState();
}

class _HearingToolState extends State<HearingTool> {
  final TonePlayer _player = TonePlayer();
  final List<double> _levels = hearingLevels();
  bool _running = false;
  int _ear = 0, _freq = 0, _lv = 0;
  Timer? _timer;
  final Map<String, int> _res = {};
  Map<String, Object?> _last = {};

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('last').then((m) {
      if (mounted) setState(() => _last = m);
    });
  }

  void _start() {
    _res.clear();
    setState(() {
      _running = true;
      _ear = 0;
      _freq = 0;
      _lv = 0;
    });
    _play();
  }

  void _play() {
    _timer?.cancel();
    final wav = makeStereoTone(kHearingFreqs[_freq].toDouble(), 1000, left: _ear == 0, volume: _levels[_lv]);
    unawaited(_player.play(wav));
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted || !_running) return;
      if (_lv < _levels.length - 1) {
        setState(() => _lv++);
        _play();
      } else {
        _record(null);
      }
    });
  }

  void _record(int? level) {
    _res['${_ear}_${kHearingFreqs[_freq]}'] = hearingScore(level);
    if (_freq < kHearingFreqs.length - 1) {
      _freq++;
    } else if (_ear == 0) {
      _ear = 1;
      _freq = 0;
    } else {
      _finish();
      return;
    }
    _lv = 0;
    setState(() {});
    Timer(const Duration(milliseconds: 700), () {
      if (mounted && _running) _play();
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();
    await _player.stop();
    _last = {..._res, 'at': DateTime.now().millisecondsSinceEpoch};
    await t.store.writeMap('last', _last);
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _running = false;
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Widget _chart() {
    return Column(children: [
      for (var e = 0; e < 2; e++) ...[
        Text(L(t, e == 0 ? 'left_ear' : 'right_ear'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final f in kHearingFreqs)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 8 + 80 * (((_last['${e}_$f'] as num?) ?? 0) / 9),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: e == 0 ? Colors.lightBlueAccent : Colors.pinkAccent, borderRadius: BorderRadius.circular(6)),
                  ),
                  const SizedBox(height: 4),
                  Text(f >= 1000 ? '${f ~/ 1000}k' : '$f', style: const TextStyle(fontSize: 11)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return ToolList(children: [
        AppPanel(
          child: Column(children: [
            Icon(Icons.hearing_rounded, size: 72, color: _ear == 0 ? Colors.lightBlueAccent : Colors.pinkAccent),
            Text(L(t, _ear == 0 ? 'left_ear' : 'right_ear'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            Text('${kHearingFreqs[_freq]} Hz'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_ear * kHearingFreqs.length + _freq) / (2 * kHearingFreqs.length)),
          ]),
        ),
        Center(
          child: SizedBox(
            width: 240,
            height: 96,
            child: FilledButton.icon(
              icon: const Icon(Icons.touch_app_rounded, size: 32),
              label: Text(L(t, 'i_hear'), style: const TextStyle(fontSize: 22)),
              onPressed: () {
                _timer?.cancel();
                unawaited(_player.stop());
                _record(_lv);
              },
            ),
          ),
        ),
        Center(child: TextButton(onPressed: () {
          _running = false;
          _timer?.cancel();
          unawaited(_player.stop());
          setState(() {});
        }, child: Text(L(t, 'stop')))),
      ]);
    }
    return ToolList(children: [
      AppInfoCard(L(t, 'headphones_hint'), icon: Icons.headphones_rounded),
      Center(child: AppButton(label: L(t, 'start'), icon: Icons.play_arrow_rounded, onPressed: _start)),
      if (_last.isNotEmpty) Section(L(t, 'last_result'), icon: Icons.equalizer_rounded, children: [_chart(), Text(L(t, 'hearing_scale'), style: const TextStyle(color: Colors.white60, fontSize: 12))]),
      WarnCard(L(t, 'hearing_note')),
    ]);
  }
}

// ------------------------------------------------------------ nabız

class PulseTool extends StatefulWidget {
  final ToolContext t;
  const PulseTool(this.t, {super.key});

  @override
  State<PulseTool> createState() => _PulseToolState();
}

class _PulseToolState extends State<PulseTool> {
  static const int _seconds = 20;
  bool _measuring = false;
  CameraController? _cam;
  final List<double> _sig = [];
  final List<int> _ts = [];
  bool _finger = false;
  double? _bpm;
  bool _failed = false;
  List<Map<String, Object?>> _hist = [];
  int _startMs = 0;
  Timer? _tick;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('history').then((h) {
      if (mounted) setState(() => _hist = h);
    });
  }

  Future<void> _begin(CameraController c) async {
    _cam = c;
    _sig.clear();
    _ts.clear();
    _startMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await c.setFlashMode(FlashMode.torch);
    } catch (_) {}
    try {
      await c.startImageStream((img) {
        final s = sampleFrame(img);
        if (s == null) return;
        final finger = s.r > 120 && s.r > s.g * 1.6;
        if (finger != _finger && mounted) setState(() => _finger = finger);
        if (!finger) {
          _sig.clear();
          _ts.clear();
          _startMs = DateTime.now().millisecondsSinceEpoch;
          return;
        }
        _sig.add(s.luma);
        _ts.add(DateTime.now().millisecondsSinceEpoch);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_finger && DateTime.now().millisecondsSinceEpoch - _startMs >= _seconds * 1000) {
        _complete();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _complete() async {
    _tick?.cancel();
    final secs = _ts.length < 2 ? 0 : (_ts.last - _ts.first) / 1000;
    final fps = secs <= 0 ? 0.0 : (_ts.length - 1) / secs;
    final bpm = estimateBpm(List<double>.of(_sig), fps);
    await _stopCam();
    if (bpm != null) {
      _hist = <Map<String, Object?>>[
        {'at': DateTime.now().millisecondsSinceEpoch, 'bpm': bpm.round()},
        ..._hist,
      ].take(50).toList();
      await t.store.writeList('history', _hist);
    }
    if (mounted) {
      setState(() {
        _measuring = false;
        _bpm = bpm;
        _failed = bpm == null;
      });
    }
  }

  Future<void> _stopCam() async {
    final c = _cam;
    _cam = null;
    if (c == null) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
    try {
      await c.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_stopCam());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return ToolList(children: [notAvailable(t), WarnCard(L(t, 'pulse_note'))]);
    final loc = MaterialLocalizations.of(context);
    if (_measuring) {
      final el = (DateTime.now().millisecondsSinceEpoch - _startMs) / 1000;
      final shown = _sig.length > 150 ? _sig.sublist(_sig.length - 150) : _sig;
      return ToolList(children: [
        CameraBox(
          tool: t,
          preset: ResolutionPreset.low,
          onReady: _begin,
          builder: (_, c) => SizedBox(height: 1, width: 1, child: cameraPreview(c, height: 1)),
        ),
        AppPanel(
          child: Column(children: [
            Icon(Icons.fingerprint_rounded, size: 64, color: _finger ? Colors.redAccent : Colors.white38),
            Text(L(t, _finger ? 'hold_still' : 'cover_lens'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _finger ? (el / _seconds).clamp(0.0, 1.0) : 0),
          ]),
        ),
        if (shown.length > 10) Sparkline(shown, height: 80),
        Center(child: TextButton(onPressed: () async {
          _tick?.cancel();
          await _stopCam();
          if (mounted) setState(() => _measuring = false);
        }, child: Text(L(t, 'stop')))),
      ]);
    }
    return ToolList(children: [
      if (_bpm != null) BigReadout(fmt(_bpm!, 0), unit: L(t, 'bpm'), caption: L(t, 'estimate')),
      if (_failed) AppInfoCard(L(t, 'signal_weak'), icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded),
      AppInfoCard(L(t, 'cover_lens'), icon: Icons.touch_app_rounded),
      Center(
        child: AppButton(
          label: L(t, 'start'),
          icon: Icons.favorite_rounded,
          onPressed: () => setState(() {
            _measuring = true;
            _bpm = null;
            _failed = false;
            _finger = false;
          }),
        ),
      ),
      if (_hist.isNotEmpty)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final h in _hist.take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(loc.formatMediumDate(DateTime.fromMillisecondsSinceEpoch(((h['at'] as num?) ?? 0).toInt()))),
              trailing: Text('${h['bpm']} ${L(t, 'bpm')}'),
            ),
        ]),
      WarnCard(L(t, 'pulse_note')),
    ]);
  }
}

/// Kafein ve içecek takibi: hazır içecekler (yaklaşık değerler) ya da kendi
/// içeceğin, günlük toplam, kendi belirlediğin sınır, 7 günlük geçmiş ve
/// yarılanma ömrüyle kaba "şu an kalan" tahmini. Tıbbi değildir.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic.dart';

class CaffeineTool extends StatefulWidget {
  final ToolContext t;
  const CaffeineTool(this.t, {super.key});

  @override
  State<CaffeineTool> createState() => _CaffeineToolState();
}

class _CaffeineToolState extends State<CaffeineTool> {
  List<Map<String, Object?>> _log = [];
  List<Map<String, Object?>> _custom = [];
  double _limit = 400;
  double _half = 5;
  int _bed = 23 * 60;
  bool _loaded = false;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await t.store.readList('log');
    final custom = await t.store.readList('custom');
    final limit = await t.store.readDouble('limit', 400);
    final half = await t.store.readDouble('half', 5);
    final bed = await t.store.readInt('bed', 23 * 60);
    if (!mounted) return;
    setState(() {
      _log = log;
      _custom = custom;
      _limit = limit;
      _half = half;
      _bed = bed;
      _loaded = true;
    });
  }

  List<(DateTime, double)> get _entries => [
        for (final e in _log)
          (DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt()), ((e['mg'] as num?) ?? 0).toDouble()),
      ];

  Future<void> _add(String name, double mg, {DateTime? at}) async {
    final when = at ?? DateTime.now();
    setState(() {
      _log.insert(0, {'at': when.millisecondsSinceEpoch, 'mg': mg, 'n': name});
      _log.sort((a, b) => ((b['at'] as num?) ?? 0).compareTo((a['at'] as num?) ?? 0));
      // 120 günden eski kayıtlar silinir.
      final cut = DateTime.now().subtract(const Duration(days: 120)).millisecondsSinceEpoch;
      _log.removeWhere((e) => ((e['at'] as num?) ?? 0) < cut);
    });
    await t.store.writeList('log', _log);
  }

  Future<void> _addCustom() async {
    final name = TextEditingController();
    final mg = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L(t, 'custom_drink')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(controller: name, label: L(t, 'name')),
          AppNumberField(controller: mg, label: L(t, 'caffeine'), suffix: 'mg'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L(t, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L(t, 'save'))),
        ],
      ),
    );
    final n = name.text.trim(), v = numOf(mg);
    name.dispose();
    mg.dispose();
    if (ok != true || n.isEmpty || v == null || v < 0 || v > 2000) return;
    setState(() => _custom.add({'n': n, 'mg': v}));
    await t.store.writeList('custom', _custom);
  }

  Future<void> _pickTime(String name, double mg) async {
    final now = TimeOfDay.now();
    final r = await showTimePicker(context: context, initialTime: now);
    if (r == null) return;
    final d = DateTime.now();
    var at = DateTime(d.year, d.month, d.day, r.hour, r.minute);
    if (at.isAfter(d)) at = at.subtract(const Duration(days: 1));
    await _add(name, mg, at: at);
  }

  Widget _drinkChip(String label, double mg, {VoidCallback? onLongPress}) => Padding(
        padding: const EdgeInsets.all(3),
        child: GestureDetector(
          onLongPress: onLongPress ?? () => _pickTime(label, mg),
          child: ActionChip(
            avatar: const Icon(Icons.local_cafe_rounded, size: 18),
            label: Text('$label · ${mg.round()} mg'),
            onPressed: () => _add(label, mg),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final s = AppLook.of(context);
    final now = DateTime.now();
    final entries = _entries;
    final byDay = caffeineByDay(entries);
    final today = byDay[isoDay(now)] ?? 0;
    final inBody = caffeineAt(entries, now, halfLifeHours: _half);
    final bed = DateTime(now.year, now.month, now.day, _bed ~/ 60, _bed % 60);
    final bedT = bed.isBefore(now) ? bed.add(const Duration(days: 1)) : bed;
    final atBed = caffeineAt(entries, bedT, halfLifeHours: _half);
    final low = caffeineBelow(entries, now, 50, halfLifeHours: _half);
    final week = [
      for (var i = 6; i >= 0; i--) byDay[isoDay(now.subtract(Duration(days: i)))] ?? 0.0,
    ];
    final curve = [for (var h = 0; h <= 24; h++) caffeineAt(entries, now.add(Duration(hours: h - 12)), halfLifeHours: _half)];
    final todayLog = _log.where((e) => isoDay(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt())) == isoDay(now)).toList();
    final over = today > _limit;
    return ToolList(children: [
      BigReadout('${today.round()}', unit: 'mg', caption: L(t, 'today')),
      AppPanel(
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _limit <= 0 ? 0 : math.min(1, today / _limit),
              minHeight: 12,
              color: over ? Colors.orangeAccent : s.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text('${L(t, 'my_limit')}: ${_limit.round()} mg', style: const TextStyle(color: Colors.white70)),
          if (over) Text(L(t, 'over_limit'), style: const TextStyle(color: Colors.orangeAccent)),
        ]),
      ),
      Section(L(t, 'add_drink'), icon: Icons.local_cafe_rounded, children: [
        Wrap(children: [
          for (final d in kDrinks) _drinkChip(L(t, d.key), d.mg.toDouble()),
          for (var i = 0; i < _custom.length; i++)
            _drinkChip('${_custom[i]['n']}', ((_custom[i]['mg'] as num?) ?? 0).toDouble(), onLongPress: () async {
              if (!await confirm(context, t, L(t, 'delete_q'))) return;
              setState(() => _custom.removeAt(i));
              await t.store.writeList('custom', _custom);
            }),
          Padding(
            padding: const EdgeInsets.all(3),
            child: ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: Text(L(t, 'custom_drink')), onPressed: _addCustom),
          ),
        ]),
        Text(L(t, 'drink_hint'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
      Section(L(t, 'in_body'), icon: Icons.show_chart_rounded, children: [
        AppResult(label: L(t, 'now'), value: '≈ ${inBody.round()} mg', lang: t.lang),
        AppResult(label: '${L(t, 'bedtime')} (${hm(_bed)})', value: '≈ ${atBed.round()} mg', lang: t.lang),
        if (low != null && inBody > 50) AppResult(label: L(t, 'below_50'), value: hm(low.hour * 60 + low.minute), lang: t.lang),
        Sparkline(curve, min: 0),
        Text(L(t, 'curve_hint'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
      Section(L(t, 'last_7'), icon: Icons.bar_chart_rounded, children: [
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${week[i].round()}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                    Container(
                      height: 80 * (week[i] / math.max(_limit, week.reduce(math.max))).clamp(0.02, 1.0),
                      decoration: BoxDecoration(
                        color: week[i] > _limit ? Colors.orangeAccent : s.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(MaterialLocalizations.of(context).narrowWeekdays[now.subtract(Duration(days: 6 - i)).weekday % 7],
                        style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
      if (todayLog.isNotEmpty)
        Section(L(t, 'entries'), icon: Icons.list_rounded, children: [
          for (final e in todayLog)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(hm(DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt()).hour * 60 +
                  DateTime.fromMillisecondsSinceEpoch(((e['at'] as num?) ?? 0).toInt()).minute)),
              title: Text('${e['n'] ?? ''}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${((e['mg'] as num?) ?? 0).round()} mg'),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    setState(() => _log.remove(e));
                    await t.store.writeList('log', _log);
                  },
                ),
              ]),
            ),
        ]),
      Section(L(t, 'settings'), icon: Icons.tune_rounded, children: [
        SliderRow(
          label: L(t, 'my_limit'),
          value: _limit,
          min: 50,
          max: 800,
          divisions: 30,
          text: (v) => '${v.round()} mg',
          onChanged: (v) {
            setState(() => _limit = v);
            t.store.write('limit', '$v');
          },
        ),
        SliderRow(
          label: L(t, 'half_life'),
          value: _half,
          min: 2,
          max: 10,
          divisions: 16,
          text: (v) => '${fmt(v)} ${L(t, 'h_short')}',
          onChanged: (v) {
            setState(() => _half = v);
            t.store.write('half', '$v');
          },
        ),
        TimeRow(
          label: L(t, 'bedtime'),
          minute: _bed,
          onChanged: (m) {
            setState(() => _bed = m);
            t.store.write('bed', '$m');
          },
        ),
      ]),
      WarnCard(L(t, 'caffeine_note')),
    ]);
  }
}

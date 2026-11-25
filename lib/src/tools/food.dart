/// Beslenme ve beden: su, kalori, makro, aralıklı oruç, kilo, VKİ.
/// Yeme bozukluğu riskine karşı: kalori hedefi alt sınırın altına inmez,
/// hedef kilo sağlıklı aralığın altına ayarlanamaz, oruç 20 saati aşmaz.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../data.dart';
import '../logic.dart';
import '../platform/notify.dart';

/// Ortak profil alanları (cinsiyet, yaş, boy, kilo, etkinlik).
class Profile {
  bool male;
  int age;
  double cm, kg;
  int activity;
  Profile({this.male = false, this.age = 30, this.cm = 170, this.kg = 70, this.activity = 1});

  factory Profile.from(Map<String, Object?> m) => Profile(
        male: m['male'] == true,
        age: (m['age'] as num?)?.toInt() ?? 30,
        cm: (m['cm'] as num?)?.toDouble() ?? 170,
        kg: (m['kg'] as num?)?.toDouble() ?? 70,
        activity: (m['act'] as num?)?.toInt() ?? 1,
      );
  Map<String, Object?> toJson() => {'male': male, 'age': age, 'cm': cm, 'kg': kg, 'act': activity};
}

/// Profil düzenleme paneli.
class ProfilePanel extends StatelessWidget {
  final ToolContext t;
  final Profile p;
  final VoidCallback onChanged;
  final bool activity;
  const ProfilePanel({super.key, required this.t, required this.p, required this.onChanged, this.activity = true});

  @override
  Widget build(BuildContext context) {
    void upd(VoidCallback f) {
      f();
      onChanged();
    }

    return Section(L(t, 'profile'), icon: Icons.person_rounded, children: [
      Choice<bool>(
        values: const [false, true],
        labels: [L(t, 'female'), L(t, 'male')],
        selected: p.male,
        onChanged: (v) => upd(() => p.male = v),
      ),
      SliderRow(label: L(t, 'age'), value: p.age.toDouble(), min: 14, max: 90, divisions: 76,
          text: (v) => '${v.round()}', onChanged: (v) => upd(() => p.age = v.round())),
      SliderRow(label: L(t, 'height'), value: p.cm, min: 120, max: 220, divisions: 100,
          text: (v) => '${v.round()} cm', onChanged: (v) => upd(() => p.cm = v.roundToDouble())),
      SliderRow(label: L(t, 'weight'), value: p.kg, min: 35, max: 200, divisions: 330,
          text: (v) => '${fmt(v)} kg', onChanged: (v) => upd(() => p.kg = (v * 2).round() / 2)),
      if (activity)
        Pick<int>(
          label: L(t, 'activity'),
          values: const [0, 1, 2, 3, 4],
          text: (i) => L(t, 'act_$i'),
          value: p.activity,
          onChanged: (v) => upd(() => p.activity = v),
        ),
    ]);
  }
}

/// Yeme bozukluğu için destek bilgisi (her beslenme aracında görünür).
Widget edHelp(ToolContext t) => WarnCard(L(t, 'ed_help'), icon: Icons.volunteer_activism_rounded);

// ------------------------------------------------------------------ su

class WaterTool extends StatefulWidget {
  final ToolContext t;
  const WaterTool(this.t, {super.key});

  @override
  State<WaterTool> createState() => _WaterToolState();
}

class _WaterToolState extends State<WaterTool> {
  int _goal = 2000;
  Map<String, Object?> _log = {};
  List<int> _undo = [];
  bool _remind = false;
  int _from = 9 * 60, _to = 21 * 60, _every = 90;
  final _kg = TextEditingController();

  ToolContext get t => widget.t;
  String get _today => isoDay(DateTime.now());
  int _day(String d) => (_log[d] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _goal = await t.store.readInt('goal', 2000);
    _log = await t.store.readMap('log');
    final r = await t.store.readMap('remind');
    _remind = r['on'] == true;
    _from = (r['from'] as num?)?.toInt() ?? _from;
    _to = (r['to'] as num?)?.toInt() ?? _to;
    _every = (r['every'] as num?)?.toInt() ?? _every;
    if (mounted) setState(() {});
  }

  Future<void> _add(int ml) async {
    setState(() {
      _log[_today] = (_day(_today) + ml).clamp(0, 20000);
      _undo = [..._undo, ml];
    });
    final keys = _log.keys.toList()..sort();
    while (keys.length > 90) {
      _log.remove(keys.removeAt(0));
    }
    await t.store.writeMap('log', _log);
  }

  Future<void> _saveRemind(bool on) async {
    if (on) await askNotifyOnce(context, t);
    setState(() => _remind = on);
    await t.store.writeMap('remind', {'on': on, 'from': _from, 'to': _to, 'every': _every});
    if (on) {
      await scheduleDaily(base: 32000, minutes: reminderSlots(_from, _to, _every), title: L(t, 'n_water_title'), body: L(t, 'n_water_body'));
    } else {
      await cancelDaily(32000);
    }
  }

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final today = _day(_today);
    final days = [for (var i = 6; i >= 0; i--) isoDay(DateTime.now().subtract(Duration(days: i)))];
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (today / _goal).clamp(0.0, 1.0),
                  strokeWidth: 16,
                  color: Colors.lightBlueAccent,
                  backgroundColor: Colors.white12,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$today', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: s.number)),
                Text('/ $_goal ml'),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final ml in const [150, 250, 330, 500])
              FilledButton.tonalIcon(
                icon: const Icon(Icons.local_drink_rounded),
                label: Text('+$ml ml'),
                onPressed: () => _add(ml),
              ),
            if (_undo.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.undo_rounded),
                label: Text(L(t, 'undo')),
                onPressed: () {
                  final last = _undo.last;
                  _undo = _undo.sublist(0, _undo.length - 1);
                  _add(-last);
                  _undo = _undo.sublist(0, _undo.length - 1);
                },
              ),
          ]),
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
                    height: 90 * (_day(d) / _goal).clamp(0.02, 1.0),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _day(d) >= _goal ? Colors.lightBlueAccent : Colors.lightBlueAccent.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(d.substring(8), style: const TextStyle(fontSize: 11)),
                ]),
              ),
          ]),
        ),
      ]),
      Section(L(t, 'daily_goal'), icon: Icons.flag_rounded, children: [
        SliderRow(
          label: L(t, 'goal'),
          value: _goal.toDouble(),
          min: 1000,
          max: 4000,
          divisions: 12,
          text: (v) => '${v.round()} ml',
          onChanged: (v) {
            setState(() => _goal = v.round());
            t.store.write('goal', '$_goal');
          },
        ),
        Row(children: [
          Expanded(child: AppNumberField(controller: _kg, label: L(t, 'weight'), suffix: 'kg', decimal: true)),
          TextButton(
            onPressed: () {
              final kg = numOf(_kg);
              if (kg == null || kg < 25 || kg > 300) return;
              setState(() => _goal = waterGoalMl(kg));
              t.store.write('goal', '$_goal');
            },
            child: Text(L(t, 'suggest')),
          ),
        ]),
        Text(L(t, 'water_hint'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
      Section(L(t, 'reminders'), icon: Icons.notifications_rounded, children: [
        if (!Notify.supported) notAvailable(t),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L(t, 'remind_me')),
          value: _remind,
          onChanged: Notify.supported ? _saveRemind : null,
        ),
        TimeRow(label: L(t, 'from'), minute: _from, onChanged: (v) => setState(() => _from = v)),
        TimeRow(label: L(t, 'to'), minute: _to, onChanged: (v) => setState(() => _to = v)),
        SliderRow(
          label: L(t, 'every'),
          value: _every.toDouble(),
          min: 30,
          max: 240,
          divisions: 14,
          text: (v) => '${v.round()} ${L(t, 'min_short')}',
          onChanged: (v) => setState(() => _every = v.round()),
        ),
        if (_remind) TextButton(onPressed: () => _saveRemind(true), child: Text(L(t, 'apply'))),
      ]),
    ]);
  }
}

// ----------------------------------------------------------- besin seçici

/// Kullanıcının eklediği besin (100 g başına).
class CustomFood {
  final String name;
  final double kcal, protein, carbs, fat;
  const CustomFood(this.name, this.kcal, this.protein, this.carbs, this.fat);
  factory CustomFood.from(Map<String, Object?> m) => CustomFood(
        '${m['name'] ?? ''}',
        (m['kcal'] as num?)?.toDouble() ?? 0,
        (m['p'] as num?)?.toDouble() ?? 0,
        (m['c'] as num?)?.toDouble() ?? 0,
        (m['f'] as num?)?.toDouble() ?? 0,
      );
  Map<String, Object?> toJson() => {'name': name, 'kcal': kcal, 'p': protein, 'c': carbs, 'f': fat};
}

/// Arama kutulu besin listesi; seçilince [onPick] (ad, 100 g değerleri).
class FoodSearch extends StatefulWidget {
  final ToolContext t;
  final List<CustomFood> custom;
  final void Function(String name, String? key, double kcal, double p, double c, double f) onPick;
  const FoodSearch({super.key, required this.t, required this.custom, required this.onPick});

  @override
  State<FoodSearch> createState() => _FoodSearchState();
}

class _FoodSearchState extends State<FoodSearch> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final q = _q.text.trim().toLowerCase();
    final foods = [
      for (final f in kFoods)
        if (q.isEmpty || L(t, 'f_${f.key}').toLowerCase().contains(q)) f,
    ];
    final customs = [
      for (final c in widget.custom)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(controller: _q, label: L(t, 'search_food'), onChanged: (_) => setState(() {})),
      SizedBox(
        height: 260,
        child: ListView(children: [
          for (final c in customs)
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_note_rounded),
              title: Text(c.name),
              subtitle: Text('${fmt(c.kcal, 0)} kcal · P ${fmt(c.protein)} · C ${fmt(c.carbs)} · F ${fmt(c.fat)} / 100 g'),
              onTap: () => widget.onPick(c.name, null, c.kcal, c.protein, c.carbs, c.fat),
            ),
          for (final f in foods)
            ListTile(
              dense: true,
              leading: Icon(f.usda ? Icons.eco_rounded : Icons.restaurant_rounded),
              title: Text(L(t, 'f_${f.key}')),
              subtitle: Text('${fmt(f.kcal, 0)} kcal · P ${fmt(f.protein)} · C ${fmt(f.carbs)} · F ${fmt(f.fat)} / 100 g'),
              onTap: () => widget.onPick(L(t, 'f_${f.key}'), f.key, f.kcal, f.protein, f.carbs, f.fat),
            ),
        ]),
      ),
    ]);
  }
}

/// Yeni özel besin penceresi.
Future<CustomFood?> askCustomFood(BuildContext context, ToolContext t) async {
  final n = TextEditingController(), k = TextEditingController(), p = TextEditingController();
  final c = TextEditingController(), f = TextEditingController();
  final r = await showDialog<CustomFood>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L(t, 'custom_food')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(controller: n, label: L(t, 'name')),
          AppNumberField(controller: k, label: 'kcal / 100 g', decimal: true),
          AppNumberField(controller: p, label: '${L(t, 'protein')} (g)', decimal: true),
          AppNumberField(controller: c, label: '${L(t, 'carbs')} (g)', decimal: true),
          AppNumberField(controller: f, label: '${L(t, 'fat')} (g)', decimal: true),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L(t, 'cancel'))),
        FilledButton(
          onPressed: () {
            final kcal = numOf(k);
            if (n.text.trim().isEmpty || kcal == null || kcal < 0 || kcal > 950) return;
            Navigator.pop(ctx, CustomFood(n.text.trim(), kcal, numOf(p) ?? 0, numOf(c) ?? 0, numOf(f) ?? 0));
          },
          child: Text(L(t, 'save')),
        ),
      ],
    ),
  );
  for (final x in [n, k, p, c, f]) {
    x.dispose();
  }
  return r;
}

// -------------------------------------------------------------- kalori

class CalorieTool extends StatefulWidget {
  final ToolContext t;
  const CalorieTool(this.t, {super.key});

  @override
  State<CalorieTool> createState() => _CalorieToolState();
}

class _CalorieToolState extends State<CalorieTool> {
  int _goal = 2000;
  bool _male = false;
  bool _clamped = false;
  List<Map<String, Object?>> _entries = [];
  List<CustomFood> _custom = [];
  int _meal = 0;
  bool _adding = false;
  final _goalCtl = TextEditingController();

  ToolContext get t => widget.t;
  String get _today => isoDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await t.store.readMap('goal');
    _goal = (g['kcal'] as num?)?.toInt() ?? 2000;
    _male = g['male'] == true;
    _goalCtl.text = '$_goal';
    _entries = await t.store.readList('entries');
    _custom = [for (final m in await t.store.readList('custom')) CustomFood.from(m)];
    if (mounted) setState(() {});
  }

  Future<void> _setGoal() async {
    final v = numOf(_goalCtl)?.round();
    if (v == null) return;
    final r = clampCalorieGoal(v.clamp(0, 6000), _male);
    setState(() {
      _goal = r.kcal;
      _clamped = r.clamped;
      _goalCtl.text = '$_goal';
    });
    await t.store.writeMap('goal', {'kcal': _goal, 'male': _male});
  }

  Future<void> _pick(String name, String? key, double kcal, double p, double c, double f) async {
    final grams = TextEditingController(text: '100');
    final g = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: AppNumberField(controller: grams, label: L(t, 'grams'), suffix: 'g', decimal: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L(t, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, numOf(grams)), child: Text(L(t, 'add'))),
        ],
      ),
    );
    grams.dispose();
    if (g == null || g <= 0 || g > 3000) return;
    setState(() {
      _entries = [
        ..._entries,
        {
          'd': _today, 'm': _meal, 'name': name, 'key': key, 'g': g,
          'kcal': kcal * g / 100, 'p': p * g / 100, 'c': c * g / 100, 'f': f * g / 100,
        },
      ];
      // 120 günden eski kayıtlar atılır.
      final cut = isoDay(DateTime.now().subtract(const Duration(days: 120)));
      _entries = [for (final e in _entries) if ('${e['d']}'.compareTo(cut) >= 0) e];
      _adding = false;
    });
    await t.store.writeList('entries', _entries);
  }

  @override
  void dispose() {
    _goalCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = [for (final e in _entries) if (e['d'] == _today) e];
    double sum(String k) => today.fold(0.0, (a, e) => a + ((e[k] as num?)?.toDouble() ?? 0));
    final kcal = sum('kcal');
    final meals = ['breakfast', 'lunch', 'dinner', 'snack'];
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          BigReadout(fmt(kcal, 0), unit: 'kcal', caption: L(t, 'today')),
          LinearProgressIndicator(value: (kcal / _goal).clamp(0.0, 1.0), minHeight: 10),
          const SizedBox(height: 8),
          AppResult(label: L(t, 'daily_goal'), value: '$_goal kcal', lang: t.lang),
          AppResult(label: L(t, 'remaining'), value: '${fmt((_goal - kcal).clamp(0, 99999), 0)} kcal', lang: t.lang),
          AppResult(
              label: '${L(t, 'protein')} · ${L(t, 'carbs')} · ${L(t, 'fat')}',
              value: '${fmt(sum('p'), 0)} · ${fmt(sum('c'), 0)} · ${fmt(sum('f'), 0)} g',
              lang: t.lang),
        ]),
      ),
      if (!_adding)
        Center(
          child: Wrap(spacing: 10, children: [
            AppButton(label: L(t, 'log_food'), icon: Icons.add_rounded, onPressed: () => setState(() => _adding = true)),
            TextButton.icon(
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(L(t, 'custom_food')),
              onPressed: () async {
                final c = await askCustomFood(context, t);
                if (c == null) return;
                setState(() => _custom = [..._custom, c]);
                await t.store.writeList('custom', [for (final x in _custom) x.toJson()]);
              },
            ),
          ]),
        ),
      if (_adding)
        Section(L(t, 'log_food'), icon: Icons.search_rounded, children: [
          Choice<int>(values: const [0, 1, 2, 3], labels: [for (final m in meals) L(t, m)], selected: _meal,
              onChanged: (v) => setState(() => _meal = v)),
          FoodSearch(t: t, custom: _custom, onPick: _pick),
          TextButton(onPressed: () => setState(() => _adding = false), child: Text(L(t, 'cancel'))),
        ]),
      for (var m = 0; m < 4; m++)
        if (today.any((e) => e['m'] == m))
          Section(L(t, meals[m]), children: [
            for (final e in today.where((e) => e['m'] == m))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${e['name']}'),
                subtitle: Text('${fmt((e['g'] as num?) ?? 0, 0)} g'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${fmt((e['kcal'] as num?) ?? 0, 0)} kcal'),
                  IconButton(
                    tooltip: L(t, 'delete'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      setState(() => _entries = [for (final x in _entries) if (!identical(x, e)) x]);
                      await t.store.writeList('entries', _entries);
                    },
                  ),
                ]),
              ),
          ]),
      Section(L(t, 'daily_goal'), icon: Icons.flag_rounded, children: [
        Choice<bool>(values: const [false, true], labels: [L(t, 'female'), L(t, 'male')], selected: _male,
            onChanged: (v) => setState(() => _male = v)),
        Row(children: [
          Expanded(child: AppNumberField(controller: _goalCtl, label: L(t, 'goal'), suffix: 'kcal')),
          TextButton(onPressed: _setGoal, child: Text(L(t, 'save'))),
        ]),
        if (_clamped) WarnCard(Lf(t, 'goal_floor_warn', {'n': calorieFloor(_male)})),
      ]),
      AppInfoCard(L(t, 'food_source'), icon: Icons.menu_book_rounded),
      edHelp(t),
    ]);
  }
}

// --------------------------------------------------------------- makro

class MacroTool extends StatefulWidget {
  final ToolContext t;
  const MacroTool(this.t, {super.key});

  @override
  State<MacroTool> createState() => _MacroToolState();
}

class _MacroToolState extends State<MacroTool> {
  Profile _p = Profile();
  int _goal = 0;
  int _split = 0;
  String _food = 'apple';

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('profile').then((m) {
      if (!mounted) return;
      setState(() {
        _p = Profile.from(m);
        _goal = (m['goal'] as num?)?.toInt() ?? 0;
        _split = (m['split'] as num?)?.toInt() ?? 0;
      });
    });
  }

  void _save() {
    setState(() {});
    t.store.writeMap('profile', {..._p.toJson(), 'goal': _goal, 'split': _split});
  }

  @override
  Widget build(BuildContext context) {
    final adult = _p.age >= 18;
    final energy = tdee(kg: _p.kg, cm: _p.cm, age: _p.age, male: _p.male, activity: _p.activity);
    final g = calorieGoal(energy, _goal, _p.male);
    final m = macroGrams(g.kcal, kMacroSplits[_split]);
    final f = foodByKey(_food);
    return ToolList(children: [
      ProfilePanel(t: t, p: _p, onChanged: _save),
      Section(L(t, 'goal'), icon: Icons.flag_rounded, children: [
        Choice<int>(values: const [-1, 0, 1], labels: [L(t, 'goal_lose'), L(t, 'goal_keep'), L(t, 'goal_gain')], selected: _goal,
            onChanged: (v) {
              _goal = v;
              _save();
            }),
        Choice<int>(values: const [0, 1, 2], labels: [L(t, 'split_0'), L(t, 'split_1'), L(t, 'split_2')], selected: _split,
            onChanged: (v) {
              _split = v;
              _save();
            }),
      ]),
      if (!adult) WarnCard(L(t, 'adults_only')),
      if (adult)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'tdee'), value: '${fmt(energy, 0)} kcal', lang: t.lang),
            AppResult(label: L(t, 'daily_goal'), value: '${g.kcal} kcal', lang: t.lang, big: true),
            AppResult(label: L(t, 'protein'), value: '${m.protein} g', lang: t.lang),
            AppResult(label: L(t, 'carbs'), value: '${m.carbs} g', lang: t.lang),
            AppResult(label: L(t, 'fat'), value: '${m.fat} g', lang: t.lang),
            const SizedBox(height: 8),
            SizedBox(
              height: 14,
              child: Row(children: [
                Expanded(flex: kMacroSplits[_split].$1, child: Container(color: Colors.redAccent)),
                Expanded(flex: kMacroSplits[_split].$2, child: Container(color: Colors.amber)),
                Expanded(flex: kMacroSplits[_split].$3, child: Container(color: Colors.lightBlueAccent)),
              ]),
            ),
          ]),
        ),
      if (adult && g.clamped) WarnCard(Lf(t, 'goal_floor_warn', {'n': calorieFloor(_p.male)})),
      Section(L(t, 'food_lookup'), icon: Icons.search_rounded, children: [
        Pick<String>(
          label: L(t, 'food'),
          values: [for (final x in kFoods) x.key],
          text: (k) => L(t, 'f_$k'),
          value: _food,
          onChanged: (v) => setState(() => _food = v),
        ),
        if (f != null) ...[
          AppResult(label: 'kcal / 100 g', value: fmt(f.kcal, 0), lang: t.lang),
          AppResult(label: L(t, 'protein'), value: '${fmt(f.protein)} g', lang: t.lang),
          AppResult(label: L(t, 'carbs'), value: '${fmt(f.carbs)} g', lang: t.lang),
          AppResult(label: L(t, 'fat'), value: '${fmt(f.fat)} g', lang: t.lang),
        ],
      ]),
      AppInfoCard(L(t, 'macro_hint'), icon: Icons.info_outline_rounded),
      AppInfoCard(L(t, 'food_source'), icon: Icons.menu_book_rounded),
      edHelp(t),
    ]);
  }
}

// ---------------------------------------------------------------- oruç

class FastingTool extends StatefulWidget {
  final ToolContext t;
  const FastingTool(this.t, {super.key});

  @override
  State<FastingTool> createState() => _FastingToolState();
}

class _FastingToolState extends State<FastingTool> {
  int _plan = 14;
  DateTime? _start;
  List<Map<String, Object?>> _history = [];
  Timer? _tick;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _start != null) setState(() {});
    });
  }

  Future<void> _load() async {
    final m = await t.store.readMap('state');
    _plan = ((m['plan'] as num?)?.toInt() ?? 14).clamp(kFastPlans.first, kMaxFastHours);
    final s = (m['start'] as num?)?.toInt();
    _start = s == null ? null : DateTime.fromMillisecondsSinceEpoch(s);
    _history = await t.store.readList('history');
    if (mounted) setState(() {});
  }

  Future<void> _saveState() =>
      t.store.writeMap('state', {'plan': _plan, if (_start != null) 'start': _start!.millisecondsSinceEpoch});

  Future<void> _begin(DateTime at) async {
    await askNotifyOnce(context, t);
    setState(() => _start = at);
    await _saveState();
    await Notify.schedule(33000, L(t, 'fast_done_title'), L(t, 'fast_done_body'), at.add(Duration(hours: _plan)));
  }

  Future<void> _end() async {
    final s = _start;
    if (s == null) return;
    final mins = DateTime.now().difference(s).inMinutes;
    setState(() {
      _history = <Map<String, Object?>>[
        {'start': s.millisecondsSinceEpoch, 'min': mins, 'plan': _plan},
        ..._history,
      ].take(60).toList();
      _start = null;
    });
    await Notify.cancel(33000);
    await t.store.writeList('history', _history);
    await _saveState();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _start;
    final now = DateTime.now();
    return ToolList(children: [
      if (s == null) ...[
        Section(L(t, 'plan'), icon: Icons.schedule_rounded, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in kFastPlans)
              ChoiceChip(
                label: Text('$h:${24 - h}'),
                selected: _plan == h,
                onSelected: (_) {
                  setState(() => _plan = h);
                  _saveState();
                },
              ),
          ]),
          const SizedBox(height: 6),
          Text(Lf(t, 'plan_desc', {'a': _plan, 'b': 24 - _plan})),
        ]),
        Center(
          child: Wrap(spacing: 10, children: [
            AppButton(label: L(t, 'start_fast'), icon: Icons.play_arrow_rounded, onPressed: () => _begin(DateTime.now())),
            TextButton.icon(
              icon: const Icon(Icons.history_rounded),
              label: Text(L(t, 'started_earlier')),
              onPressed: () async {
                final r = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
                if (r == null) return;
                var at = DateTime(now.year, now.month, now.day, r.hour, r.minute);
                if (at.isAfter(now)) at = at.subtract(const Duration(days: 1));
                await _begin(at);
              },
            ),
          ]),
        ),
      ],
      if (s != null) ...[
        AppPanel(
          child: Column(children: [
            Text(L(t, fastProgress(s, now, _plan) >= 1 ? 'eating_window' : 'fasting_now'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            SizedBox(
              width: 210,
              height: 210,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: fastProgress(s, now, _plan),
                    strokeWidth: 16,
                    backgroundColor: Colors.white12,
                  ),
                ),
                Text(clock(now.difference(s).inSeconds, hours: true),
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
              ]),
            ),
            const SizedBox(height: 8),
            AppResult(label: L(t, 'goal'), value: '$_plan ${L(t, 'hours')}', lang: t.lang),
            AppResult(
                label: L(t, 'ends_at'),
                value: MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(s.add(Duration(hours: _plan)))),
                lang: t.lang),
          ]),
        ),
        if (now.difference(s).inHours >= _plan + 2) WarnCard(L(t, 'fast_long')),
        Center(child: AppButton(label: L(t, 'end_fast'), icon: Icons.restaurant_rounded, onPressed: _end)),
      ],
      if (_history.isNotEmpty)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final h in _history.take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                ((h['min'] as num?) ?? 0) >= ((h['plan'] as num?) ?? 0) * 60 ? Icons.check_circle_rounded : Icons.timelapse_rounded,
              ),
              title: Text(MaterialLocalizations.of(context)
                  .formatMediumDate(DateTime.fromMillisecondsSinceEpoch(((h['start'] as num?) ?? 0).toInt()))),
              trailing: Text(clock((((h['min'] as num?) ?? 0) * 60).toInt(), hours: true)),
            ),
        ]),
      WarnCard(L(t, 'fasting_warn')),
      edHelp(t),
    ]);
  }
}

// ---------------------------------------------------------------- kilo

class WeightTool extends StatefulWidget {
  final ToolContext t;
  const WeightTool(this.t, {super.key});

  @override
  State<WeightTool> createState() => _WeightToolState();
}

class _WeightToolState extends State<WeightTool> {
  List<Map<String, Object?>> _e = [];
  double _cm = 0;
  double? _target;
  bool _raised = false;
  bool _lb = false;
  final _w = TextEditingController(), _h = TextEditingController(), _tg = TextEditingController();
  DateTime _date = DateTime.now();

  ToolContext get t => widget.t;
  double _show(double kg) => _lb ? kg * 2.2046226 : kg;
  double _toKg(double v) => _lb ? v / 2.2046226 : v;
  String get _u => _lb ? 'lb' : 'kg';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _e = await t.store.readList('entries');
    final m = await t.store.readMap('cfg');
    _cm = (m['cm'] as num?)?.toDouble() ?? 0;
    _target = (m['target'] as num?)?.toDouble();
    _lb = m['lb'] == true;
    if (_cm > 0) _h.text = fmt(_cm, 0);
    if (mounted) setState(() {});
  }

  Future<void> _saveCfg() => t.store.writeMap('cfg', {'cm': _cm, if (_target != null) 'target': _target, 'lb': _lb});

  Future<void> _add() async {
    final v = numOf(_w);
    if (v == null) return;
    final kg = _toKg(v);
    if (kg < 20 || kg > 400) return;
    final d = isoDay(_date);
    setState(() {
      _e = <Map<String, Object?>>[for (final x in _e) if (x['d'] != d) x, {'d': d, 'kg': kg}]..sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
      _w.clear();
    });
    await t.store.writeList('entries', _e);
  }

  void _setTarget() {
    final v = numOf(_tg);
    if (v == null) return;
    var kg = _toKg(v);
    _raised = false;
    if (_cm > 0) {
      final s = safeTargetWeight(kg, _cm);
      kg = s.target;
      _raised = s.raised;
    }
    setState(() => _target = kg);
    _tg.text = fmt(_show(kg));
    _saveCfg();
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _tg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pts = [
      for (final x in _e) (DateTime.tryParse('${x['d']}') ?? DateTime.now(), ((x['kg'] as num?) ?? 0).toDouble()),
    ];
    final last = pts.isEmpty ? null : pts.last.$2;
    final recent = pts.where((p) => p.$1.isAfter(DateTime.now().subtract(const Duration(days: 28)))).toList();
    final trend = weeklyTrend(recent);
    final tg = _target;
    return ToolList(children: [
      Choice<bool>(values: const [false, true], labels: const ['kg', 'lb'], selected: _lb, onChanged: (v) {
        setState(() => _lb = v);
        _saveCfg();
      }),
      BigReadout(last == null ? '–' : fmt(_show(last)), unit: _u, caption: L(t, 'latest')),
      if (pts.length >= 2) Sparkline([for (final p in pts.length > 60 ? pts.sublist(pts.length - 60) : pts) _show(p.$2)]),
      if (pts.length >= 2)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'change'), value: '${fmt(_show(pts.last.$2 - pts.first.$2))} $_u', lang: t.lang),
            AppResult(label: L(t, 'trend_week'), value: '${fmt(_show(trend), 2)} $_u', lang: t.lang),
            if (_cm > 0 && last != null) AppResult(label: L(t, 'bmi'), value: fmt(bmi(last, _cm)), lang: t.lang),
            if (tg != null && last != null) AppResult(label: L(t, 'to_target'), value: '${fmt(_show(last - tg))} $_u', lang: t.lang),
          ]),
        ),
      if (last != null && recent.length >= 3 && trend < 0 && tooFastChange(trend, last)) WarnCard(L(t, 'rate_warn')),
      Section(L(t, 'add_entry'), icon: Icons.add_rounded, children: [
        DateRow(label: L(t, 'date'), value: _date, last: DateTime.now(), onChanged: (d) => setState(() => _date = d)),
        Row(children: [
          Expanded(child: AppNumberField(controller: _w, label: L(t, 'weight'), suffix: _u, decimal: true)),
          IconButton.filled(onPressed: _add, icon: const Icon(Icons.check_rounded)),
        ]),
      ]),
      Section(L(t, 'settings'), icon: Icons.tune_rounded, children: [
        AppNumberField(
          controller: _h,
          label: L(t, 'height'),
          suffix: 'cm',
          decimal: true,
          onChanged: (_) {
            final v = numOf(_h);
            if (v != null && v >= 100 && v <= 250) {
              _cm = v;
              _saveCfg();
            }
          },
        ),
        Row(children: [
          Expanded(child: AppNumberField(controller: _tg, label: L(t, 'target_weight'), suffix: _u, decimal: true)),
          TextButton(onPressed: _setTarget, child: Text(L(t, 'save'))),
        ]),
        if (_raised) WarnCard(Lf(t, 'low_target_warn', {'n': '${fmt(_show(tg ?? 0))} $_u'})),
      ]),
      if (_e.isNotEmpty)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final x in _e.reversed.take(30))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${x['d']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${fmt(_show(((x['kg'] as num?) ?? 0).toDouble()))} $_u'),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: L(t, 'delete'),
                  onPressed: () async {
                    setState(() => _e = [for (final y in _e) if (y['d'] != x['d']) y]);
                    await t.store.writeList('entries', _e);
                  },
                ),
              ]),
            ),
        ]),
      edHelp(t),
    ]);
  }
}

// ----------------------------------------------------------------- VKİ

class BmiTool extends StatefulWidget {
  final ToolContext t;
  const BmiTool(this.t, {super.key});

  @override
  State<BmiTool> createState() => _BmiToolState();
}

class _BmiToolState extends State<BmiTool> {
  final _h = TextEditingController(), _w = TextEditingController();
  bool _imp = false;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('last').then((m) {
      if (!mounted) return;
      setState(() {
        _imp = m['imp'] == true;
        _h.text = '${m['h'] ?? ''}';
        _w.text = '${m['w'] ?? ''}';
      });
    });
  }

  @override
  void dispose() {
    _h.dispose();
    _w.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = numOf(_h), w = numOf(_w);
    final cm = h == null ? null : (_imp ? h * 2.54 : h);
    final kg = w == null ? null : (_imp ? w / 2.2046226 : w);
    final ok = cm != null && kg != null && cm >= 100 && cm <= 250 && kg >= 20 && kg <= 400;
    final c = cm ?? 0, k = kg ?? 0;
    final v = ok ? bmi(k, c) : 0.0;
    final cls = bmiClass(v);
    final colors = [Colors.lightBlueAccent, Colors.greenAccent, Colors.amber, Colors.deepOrangeAccent];
    void save() => t.store.writeMap('last', {'imp': _imp, 'h': _h.text, 'w': _w.text});
    return ToolList(children: [
      Choice<bool>(values: const [false, true], labels: const ['cm · kg', 'in · lb'], selected: _imp, onChanged: (x) {
        setState(() {
          _imp = x;
          _h.clear();
          _w.clear();
        });
      }),
      AppPanel(
        child: Column(children: [
          AppNumberField(controller: _h, label: L(t, 'height'), suffix: _imp ? 'in' : 'cm', decimal: true, onChanged: (_) {
            setState(() {});
            save();
          }),
          AppNumberField(controller: _w, label: L(t, 'weight'), suffix: _imp ? 'lb' : 'kg', decimal: true, onChanged: (_) {
            setState(() {});
            save();
          }),
        ]),
      ),
      if (ok) ...[
        BigReadout(fmt(v), caption: L(t, 'bmi')),
        AppPanel(
          child: Column(children: [
            Text(L(t, 'bmi_$cls'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors[cls])),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (_, box) {
              final x = ((v - 15) / 25).clamp(0.0, 1.0) * box.maxWidth;
              return Stack(clipBehavior: Clip.none, children: [
                Row(children: [
                  Expanded(flex: 35, child: Container(height: 12, color: colors[0])),
                  Expanded(flex: 65, child: Container(height: 12, color: colors[1])),
                  Expanded(flex: 50, child: Container(height: 12, color: colors[2])),
                  Expanded(flex: 100, child: Container(height: 12, color: colors[3])),
                ]),
                Positioned(left: x - 2, top: -6, child: Container(width: 4, height: 24, color: Colors.white)),
              ]);
            }),
            const SizedBox(height: 12),
            AppResult(
              label: L(t, 'healthy_range'),
              value: _imp
                  ? '${fmt(minHealthyWeight(c) * 2.2046226, 0)}–${fmt(24.9 * (c / 100) * (c / 100) * 2.2046226, 0)} lb'
                  : '${fmt(minHealthyWeight(c), 0)}–${fmt(24.9 * (c / 100) * (c / 100), 0)} kg',
              lang: t.lang,
            ),
          ]),
        ),
      ],
      AppInfoCard(L(t, 'bmi_note'), icon: Icons.info_outline_rounded),
    ]);
  }
}

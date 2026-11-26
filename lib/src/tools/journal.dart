/// Günlükler: uyku, ruh hali (kriz desteği bilgisiyle), şükür, rüya ve
/// sigara bırakma. Hepsi yalnızca cihazda saklanır; tanı dili kullanılmaz.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../logic.dart';
import '../platform/notify.dart';

// ---------------------------------------------------------------- uyku

class SleepTool extends StatefulWidget {
  final ToolContext t;
  const SleepTool(this.t, {super.key});

  @override
  State<SleepTool> createState() => _SleepToolState();
}

class _SleepToolState extends State<SleepTool> {
  List<Map<String, Object?>> _e = [];
  int _bed = 23 * 60, _wake = 7 * 60, _q = 3;
  bool _remind = false;
  int _remindAt = 22 * 60 + 30;
  final _note = TextEditingController();

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _e = await t.store.readList('entries');
    final r = await t.store.readMap('remind');
    _remind = r['on'] == true;
    _remindAt = (r['at'] as num?)?.toInt() ?? _remindAt;
    if (_e.isNotEmpty) {
      _bed = (_e.last['bed'] as num?)?.toInt() ?? _bed;
      _wake = (_e.last['wake'] as num?)?.toInt() ?? _wake;
    }
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final d = isoDay(DateTime.now());
    setState(() {
      _e = <Map<String, Object?>>[
        for (final x in _e) if (x['d'] != d) x,
        {'d': d, 'bed': _bed, 'wake': _wake, 'q': _q, 'note': _note.text.trim()},
      ];
      if (_e.length > 365) _e = _e.sublist(_e.length - 365);
      _note.clear();
    });
    await t.store.writeList('entries', _e);
  }

  Future<void> _setRemind(bool on) async {
    if (on) await askNotifyOnce(context, t);
    setState(() => _remind = on);
    await t.store.writeMap('remind', {'on': on, 'at': _remindAt});
    if (on) {
      await scheduleDaily(base: 34000, minutes: [_remindAt], title: L(t, 'n_sleep_title'), body: L(t, 'n_sleep_body'), days: 7, slots: 1);
    } else {
      await cancelDaily(34000, days: 7, slots: 1);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = [for (final x in _e) sleepMinutes(((x['bed'] as num?) ?? 0).toInt(), ((x['wake'] as num?) ?? 0).toInt())];
    final last7 = mins.length > 7 ? mins.sublist(mins.length - 7) : mins;
    final avg = last7.isEmpty ? 0 : last7.reduce((a, b) => a + b) ~/ last7.length;
    return ToolList(children: [
      Section(L(t, 'last_night'), icon: Icons.bedtime_rounded, children: [
        TimeRow(label: L(t, 'bedtime'), minute: _bed, onChanged: (v) => setState(() => _bed = v)),
        TimeRow(label: L(t, 'waketime'), minute: _wake, onChanged: (v) => setState(() => _wake = v)),
        AppResult(label: L(t, 'duration'), value: '${sleepMinutes(_bed, _wake) ~/ 60}:${two(sleepMinutes(_bed, _wake) % 60)}', lang: t.lang),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              icon: Icon(i <= _q ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber, size: 32),
              onPressed: () => setState(() => _q = i),
            ),
        ]),
        Text(L(t, 'quality'), textAlign: TextAlign.center),
        AppTextField(controller: _note, label: L(t, 'note')),
        Center(child: AppButton(label: L(t, 'save'), icon: Icons.check_rounded, onPressed: _add)),
      ]),
      if (mins.isNotEmpty)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'avg_7'), value: '${avg ~/ 60} ${L(t, 'h_short')} ${avg % 60} ${L(t, 'min_short')}', lang: t.lang),
            if (mins.length >= 2) Sparkline([for (final m in mins.length > 30 ? mins.sublist(mins.length - 30) : mins) m / 60]),
          ]),
        ),
      if (_e.isNotEmpty)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final x in _e.reversed.take(14))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${x['d']}  ·  ${hm(((x['bed'] as num?) ?? 0).toInt())} → ${hm(((x['wake'] as num?) ?? 0).toInt())}'),
              subtitle: '${x['note'] ?? ''}'.isEmpty ? null : Text('${x['note']}'),
              trailing: Text('★' * (((x['q'] as num?) ?? 0).toInt())),
            ),
        ]),
      Section(L(t, 'reminders'), icon: Icons.notifications_rounded, children: [
        if (!Notify.supported) notAvailable(t),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L(t, 'remind_bed')),
          value: _remind,
          onChanged: Notify.supported ? _setRemind : null,
        ),
        TimeRow(label: L(t, 'time'), minute: _remindAt, onChanged: (v) {
          setState(() => _remindAt = v);
          if (_remind) _setRemind(true);
        }),
      ]),
      AppInfoCard(L(t, 'sleep_hint'), icon: Icons.info_outline_rounded),
    ]);
  }
}

// ------------------------------------------------------------- kriz bilgisi

/// Cihaz bölgesi (ör. "TR"); bilinmiyorsa boş.
String deviceCountry() => (PlatformDispatcher.instance.locale.countryCode ?? '').toUpperCase();

/// Kriz anında yardım bilgisi: acil numara, ülkeye özel destek hattı ve
/// uluslararası rehber bağlantısı. Hiçbir veri gönderilmez.
class CrisisCard extends StatelessWidget {
  final ToolContext t;
  const CrisisCard(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    final cc = deviceCountry();
    final line = kHelplines[cc];
    return AppPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.volunteer_activism_rounded, color: Colors.pinkAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(L(t, 'crisis_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 8),
        Text(L(t, 'crisis_text'), style: const TextStyle(height: 1.35)),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.local_hospital_rounded, color: Colors.redAccent),
          title: Text(Lf(t, 'crisis_emergency', {'n': emergencyNumber(cc)})),
          onTap: () => launchUrl(Uri(scheme: 'tel', path: emergencyNumber(cc))),
        ),
        if (line != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone_in_talk_rounded),
            title: Text(Lf(t, 'crisis_line', {'n': line})),
            onTap: () => launchUrl(Uri(scheme: 'tel', path: line.replaceAll(' ', ''))),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public_rounded),
          title: Text(L(t, 'crisis_find')),
          subtitle: const Text('findahelpline.com'),
          onTap: () => launchUrl(Uri.parse('https://findahelpline.com'), mode: LaunchMode.externalApplication),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ ruh hali

class MoodTool extends StatefulWidget {
  final ToolContext t;
  const MoodTool(this.t, {super.key});

  @override
  State<MoodTool> createState() => _MoodToolState();
}

class _MoodToolState extends State<MoodTool> {
  static const _faces = [
    Icons.sentiment_very_dissatisfied_rounded,
    Icons.sentiment_dissatisfied_rounded,
    Icons.sentiment_neutral_rounded,
    Icons.sentiment_satisfied_rounded,
    Icons.sentiment_very_satisfied_rounded,
  ];
  static const _colors = [Colors.deepPurpleAccent, Colors.indigoAccent, Colors.blueGrey, Colors.lightGreen, Colors.amber];
  static const _tags = ['t_calm', 't_happy', 't_grateful', 't_energetic', 't_tired', 't_stressed', 't_anxious', 't_sad', 't_lonely', 't_angry'];
  List<Map<String, Object?>> _e = [];
  int? _level;
  final Set<String> _sel = {};
  final _note = TextEditingController();
  bool _help = false;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('entries').then((e) {
      if (mounted) setState(() => _e = e);
    });
  }

  Future<void> _save() async {
    final lv = _level;
    if (lv == null) return;
    final text = _note.text.trim();
    setState(() {
      _e = <Map<String, Object?>>[
        ..._e,
        {'at': DateTime.now().millisecondsSinceEpoch, 'lv': lv, 'tags': _sel.toList(), 'note': text},
      ];
      if (_e.length > 1000) _e = _e.sublist(_e.length - 1000);
      _help = _help || lv == 0 || mentionsCrisis(text);
      _level = null;
      _sel.clear();
      _note.clear();
    });
    await t.store.writeList('entries', _e);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final recent = _e.length > 30 ? _e.sublist(_e.length - 30) : _e;
    return ToolList(children: [
      if (_help) CrisisCard(t),
      Section(L(t, 'how_feel'), icon: Icons.mood_rounded, children: [
        // Dar ekranda beş yüz sığacak kadar küçülür.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 5; i++)
              IconButton(
                iconSize: 44,
                tooltip: L(t, 'mood_$i'),
                icon: Icon(_faces[i], color: _level == i ? _colors[i] : Colors.white54),
                onPressed: () => setState(() => _level = i),
              ),
          ]),
        ),
        if (_level != null) Text(L(t, 'mood_${_level!}'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final g in _tags)
            FilterChip(
              label: Text(L(t, g)),
              selected: _sel.contains(g),
              onSelected: (v) => setState(() => v ? _sel.add(g) : _sel.remove(g)),
            ),
        ]),
        AppTextField(
          controller: _note,
          label: L(t, 'note'),
          maxLines: 3,
          onChanged: (s) {
            if (!_help && mentionsCrisis(s)) setState(() => _help = true);
          },
        ),
        Center(child: AppButton(label: L(t, 'save'), icon: Icons.check_rounded, onPressed: _level == null ? null : _save)),
      ]),
      if (recent.length >= 2)
        Section(L(t, 'trend'), icon: Icons.show_chart_rounded, children: [
          Sparkline([for (final x in recent) ((x['lv'] as num?) ?? 2).toDouble()], min: 0, max: 4),
        ]),
      if (_e.isNotEmpty)
        Section(L(t, 'history'), icon: Icons.history_rounded, children: [
          for (final x in _e.reversed.take(20))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_faces[((x['lv'] as num?) ?? 2).toInt().clamp(0, 4)], color: _colors[((x['lv'] as num?) ?? 2).toInt().clamp(0, 4)]),
              title: Text(loc.formatMediumDate(DateTime.fromMillisecondsSinceEpoch(((x['at'] as num?) ?? 0).toInt()))),
              subtitle: Text([
                for (final g in (x['tags'] as List?) ?? const []) L(t, '$g'),
                if ('${x['note'] ?? ''}'.isNotEmpty) '${x['note']}',
              ].join(' · ')),
            ),
        ]),
      if (!_help)
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.support_rounded),
            label: Text(L(t, 'need_talk')),
            onPressed: () => setState(() => _help = true),
          ),
        ),
      AppInfoCard(L(t, 'mood_hint'), icon: Icons.lock_rounded),
    ]);
  }
}

// --------------------------------------------------------------- şükür

class GratitudeTool extends StatefulWidget {
  final ToolContext t;
  const GratitudeTool(this.t, {super.key});

  @override
  State<GratitudeTool> createState() => _GratitudeToolState();
}

class _GratitudeToolState extends State<GratitudeTool> {
  Map<String, Object?> _days = {};
  final _c = [TextEditingController(), TextEditingController(), TextEditingController()];
  late final int _prompt = math.Random().nextInt(6);

  ToolContext get t => widget.t;
  String get _today => isoDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    t.store.readMap('days').then((m) {
      if (!mounted) return;
      final items = (m[_today] as List?) ?? const [];
      for (var i = 0; i < 3 && i < items.length; i++) {
        _c[i].text = '${items[i]}';
      }
      setState(() => _days = m);
    });
  }

  Future<void> _save() async {
    final items = [for (final c in _c) c.text.trim()].where((s) => s.isNotEmpty).toList();
    setState(() {
      if (items.isEmpty) {
        _days.remove(_today);
      } else {
        _days[_today] = items;
      }
    });
    await t.store.writeMap('days', _days);
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'saved'))));
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = _days.keys.toList()..sort((a, b) => b.compareTo(a));
    return ToolList(children: [
      AppPanel(
        child: Row(children: [
          Expanded(child: AppResult(label: L(t, 'streak'), value: '${streak(_days.keys, DateTime.now())}', lang: t.lang)),
          Expanded(child: AppResult(label: L(t, 'entries'), value: '${_days.length}', lang: t.lang)),
        ]),
      ),
      Section(L(t, 'today'), icon: Icons.favorite_rounded, children: [
        Text(L(t, 'g_p$_prompt'), style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
        for (var i = 0; i < 3; i++) AppTextField(controller: _c[i], label: '${i + 1}.'),
        Center(child: AppButton(label: L(t, 'save'), icon: Icons.check_rounded, onPressed: _save)),
      ]),
      for (final k in keys.where((k) => k != _today).take(30))
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final s in (_days[k] as List?) ?? const []) Text('• $s'),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- rüya

class DreamTool extends StatefulWidget {
  final ToolContext t;
  const DreamTool(this.t, {super.key});

  @override
  State<DreamTool> createState() => _DreamToolState();
}

class _DreamToolState extends State<DreamTool> {
  static const _tags = ['d_lucid', 'd_vivid', 'd_recurring', 'd_nightmare', 'd_funny', 'd_flying'];
  List<Map<String, Object?>> _e = [];
  final _title = TextEditingController(), _text = TextEditingController(), _q = TextEditingController();
  final Set<String> _sel = {};
  bool _writing = false;
  int? _editAt;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('dreams').then((e) {
      if (mounted) setState(() => _e = e);
    });
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty && _title.text.trim().isEmpty) return;
    final at = _editAt ?? DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _e = <Map<String, Object?>>[
        for (final x in _e) if (x['at'] != at) x,
        {'at': at, 'title': _title.text.trim(), 'text': _text.text.trim(), 'tags': _sel.toList()},
      ]..sort((a, b) => ((a['at'] as num?) ?? 0).compareTo((b['at'] as num?) ?? 0));
      _writing = false;
      _editAt = null;
      _title.clear();
      _text.clear();
      _sel.clear();
    });
    await t.store.writeList('dreams', _e);
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final x in _e.reversed)
        if (q.isEmpty || '${x['title']} ${x['text']}'.toLowerCase().contains(q)) x,
    ];
    if (_writing) {
      return ToolList(children: [
        Section(L(t, 'new_dream'), icon: Icons.nightlight_round, children: [
          AppTextField(controller: _title, label: L(t, 'title')),
          AppTextField(controller: _text, label: L(t, 'dream_text'), maxLines: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in _tags)
              FilterChip(
                label: Text(L(t, g)),
                selected: _sel.contains(g),
                onSelected: (v) => setState(() => v ? _sel.add(g) : _sel.remove(g)),
              ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => setState(() => _writing = false), child: Text(L(t, 'cancel'))),
            AppButton(label: L(t, 'save'), icon: Icons.check_rounded, onPressed: _save),
          ]),
        ]),
      ]);
    }
    return ToolList(children: [
      Center(
        child: AppButton(
          label: L(t, 'new_dream'),
          icon: Icons.edit_rounded,
          onPressed: () => setState(() {
            _writing = true;
            _editAt = null;
          }),
        ),
      ),
      if (_e.isNotEmpty) AppTextField(controller: _q, label: L(t, 'search'), onChanged: (_) => setState(() {})),
      if (_e.isEmpty) AppInfoCard(L(t, 'dream_hint'), icon: Icons.nightlight_round),
      for (final x in list.take(50))
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${x['title']}'.isEmpty ? loc.formatMediumDate(DateTime.fromMillisecondsSinceEpoch(((x['at'] as num?) ?? 0).toInt())) : '${x['title']}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: L(t, 'edit'),
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => setState(() {
                  _writing = true;
                  _editAt = ((x['at'] as num?) ?? 0).toInt();
                  _title.text = '${x['title'] ?? ''}';
                  _text.text = '${x['text'] ?? ''}';
                  _sel
                    ..clear()
                    ..addAll([for (final g in (x['tags'] as List?) ?? const []) '$g']);
                }),
              ),
              IconButton(
                tooltip: L(t, 'delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirm(context, t, L(t, 'delete_q'))) return;
                  setState(() => _e = [for (final y in _e) if (y['at'] != x['at']) y]);
                  await t.store.writeList('dreams', _e);
                },
              ),
            ]),
            Text(loc.formatMediumDate(DateTime.fromMillisecondsSinceEpoch(((x['at'] as num?) ?? 0).toInt())),
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            if ('${x['text']}'.isNotEmpty) Text('${x['text']}', maxLines: 6, overflow: TextOverflow.ellipsis),
            if (((x['tags'] as List?) ?? const []).isNotEmpty)
              Wrap(spacing: 6, children: [for (final g in (x['tags'] as List?) ?? const []) Chip(label: Text(L(t, '$g')))]),
          ]),
        ),
    ]);
  }
}

// -------------------------------------------------------------- sigara

class SmokingTool extends StatefulWidget {
  final ToolContext t;
  const SmokingTool(this.t, {super.key});

  @override
  State<SmokingTool> createState() => _SmokingToolState();
}

class _SmokingToolState extends State<SmokingTool> {
  DateTime? _quit;
  int _perDay = 15, _pack = 20, _cravings = 0, _bestDays = 0;
  final _price = TextEditingController(text: '100');
  Timer? _tick;
  int _wave = 0; // istek dalgası geri sayımı (s)

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_wave > 0) _wave--;
      });
    });
  }

  Future<void> _load() async {
    final m = await t.store.readMap('cfg');
    final q = (m['quit'] as num?)?.toInt();
    _quit = q == null ? null : DateTime.fromMillisecondsSinceEpoch(q);
    _perDay = (m['perDay'] as num?)?.toInt() ?? _perDay;
    _pack = (m['pack'] as num?)?.toInt() ?? _pack;
    _price.text = fmt((m['price'] as num?) ?? 100, 2);
    _cravings = (m['cravings'] as num?)?.toInt() ?? 0;
    _bestDays = (m['best'] as num?)?.toInt() ?? 0;
    if (mounted) setState(() {});
  }

  Future<void> _save() => t.store.writeMap('cfg', {
        if (_quit != null) 'quit': _quit!.millisecondsSinceEpoch,
        'perDay': _perDay,
        'pack': _pack,
        'price': numOf(_price) ?? 0,
        'cravings': _cravings,
        'best': _bestDays,
      });

  @override
  void dispose() {
    _tick?.cancel();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _quit;
    final now = DateTime.now();
    final settings = Section(L(t, 'settings'), icon: Icons.tune_rounded, children: [
      SliderRow(label: L(t, 'per_day'), value: _perDay.toDouble(), min: 1, max: 60, divisions: 59,
          text: (v) => '${v.round()}', onChanged: (v) {
        setState(() => _perDay = v.round());
        _save();
      }),
      SliderRow(label: L(t, 'pack_size'), value: _pack.toDouble(), min: 10, max: 40, divisions: 30,
          text: (v) => '${v.round()}', onChanged: (v) {
        setState(() => _pack = v.round());
        _save();
      }),
      AppNumberField(controller: _price, label: L(t, 'pack_price'), decimal: true, onChanged: (_) {
        setState(() {});
        _save();
      }),
    ]);
    if (q == null) {
      return ToolList(children: [
        AppInfoCard(L(t, 'quit_intro'), icon: Icons.smoke_free_rounded),
        settings,
        Center(
          child: AppButton(
            label: L(t, 'quit_now'),
            icon: Icons.flag_rounded,
            onPressed: () {
              setState(() => _quit = DateTime.now());
              _save();
            },
          ),
        ),
      ]);
    }
    final d = now.difference(q);
    final r = smokeFree(q, now, _perDay, numOf(_price) ?? 0, _pack);
    final mins = d.inMinutes;
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Text(L(t, 'smoke_free'), style: const TextStyle(fontSize: 16)),
          FittedBox(
            child: Text('${d.inDays} ${L(t, 'd_short')}  ${d.inHours % 24} ${L(t, 'h_short')}  ${d.inMinutes % 60} ${L(t, 'min_short')}',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
          ),
          AppResult(label: L(t, 'not_smoked'), value: '${r.cigarettes}', lang: t.lang),
          AppResult(label: L(t, 'saved_money'), value: fmt(r.money, 2), lang: t.lang),
          if (_bestDays > 0) AppResult(label: L(t, 'best_streak'), value: '${math.max<int>(_bestDays, d.inDays)} ${L(t, 'd_short')}', lang: t.lang),
          AppResult(label: L(t, 'cravings_beaten'), value: '$_cravings', lang: t.lang),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          if (_wave > 0) ...[
            Text(L(t, 'wave_text'), textAlign: TextAlign.center),
            Text(clock(_wave), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
          ] else
            AppButton(
              label: L(t, 'craving'),
              icon: Icons.waves_rounded,
              onPressed: () {
                setState(() {
                  _wave = 180;
                  _cravings++;
                });
                _save();
              },
            ),
        ]),
      ),
      Section(L(t, 'milestones'), icon: Icons.timeline_rounded, children: [
        for (var i = 0; i < kQuitMilestones.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(mins >= kQuitMilestones[i] ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: mins >= kQuitMilestones[i] ? Colors.greenAccent : Colors.white38),
            title: Text(L(t, 'ms_$i')),
          ),
        Text(L(t, 'ms_note'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
      settings,
      Center(
        child: TextButton.icon(
          icon: const Icon(Icons.restart_alt_rounded),
          label: Text(L(t, 'slipped')),
          onPressed: () async {
            if (!await confirm(context, t, L(t, 'slipped_q'))) return;
            setState(() {
              _bestDays = math.max<int>(_bestDays, d.inDays);
              _quit = DateTime.now();
            });
            await _save();
          },
        ),
      ),
      AppInfoCard(L(t, 'quit_help'), icon: Icons.support_agent_rounded),
    ]);
  }
}

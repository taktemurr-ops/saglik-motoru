import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saglik_motoru/saglik_motoru.dart';
import 'package:studio_core/app/services/ads.dart';
import 'package:studio_core/app/services/purchases.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/core/save_store.dart';

void main() {
  test('33 araç, 33 dilde ad ve açıklama, hepsinde esenlik uyarısı', () {
    expect(saglikTools.length, 33);
    expect(saglikTools.map((t) => t.id).toSet().length, 33);
    for (final t in saglikTools) {
      expect(t.title.length, 33, reason: t.id);
      expect(t.tagline.length, 33, reason: t.id);
      expect(t.id.startsWith('uyg-'), isTrue);
      expect(t.disclaimer, AppDisclaimer.wellness, reason: t.id);
      expect(saglikCategories.any((c) => c.id == t.category), isTrue, reason: t.id);
    }
    for (final id in saglikFeatured) {
      expect(saglikTools.any((t) => t.id == id), isTrue, reason: id);
    }
    expect(saglikHubTitle.length, 33);
  });

  test('VKİ ve güvenli hedef kilo', () {
    expect(bmi(70, 175), closeTo(22.86, 0.01));
    expect(bmiClass(17), 0);
    expect(bmiClass(22), 1);
    expect(bmiClass(27), 2);
    expect(bmiClass(31), 3);
    final s = safeTargetWeight(40, 170);
    expect(s.raised, isTrue);
    expect(s.target, greaterThanOrEqualTo(minHealthyWeight(170)));
    expect(safeTargetWeight(65, 170).raised, isFalse);
    expect(tooFastChange(-1.5, 80), isTrue);
    expect(tooFastChange(-0.5, 80), isFalse);
  });

  test('kalori hedefi alt sınırın altına inmez (yeme bozukluğu koruması)', () {
    expect(calorieGoal(1300, -1, false).kcal, 1200);
    expect(calorieGoal(1300, -1, false).clamped, isTrue);
    expect(calorieGoal(1700, -1, true).kcal, 1500);
    expect(calorieGoal(2500, 0, true).kcal, 2500);
    expect(clampCalorieGoal(800, false).kcal, 1200);
    expect(clampCalorieGoal(800, false).clamped, isTrue);
    expect(clampCalorieGoal(1800, false).clamped, isFalse);
    final e = tdee(kg: 70, cm: 175, age: 30, male: true, activity: 1);
    expect(e, closeTo((10 * 70 + 6.25 * 175 - 150 + 5) * 1.375, 0.01));
  });

  test('makro gramları kaloriyle tutarlı', () {
    for (final split in kMacroSplits) {
      expect(split.$1 + split.$2 + split.$3, 100);
      final g = macroGrams(2000, split);
      final kcal = g.protein * 4 + g.carbs * 4 + g.fat * 9;
      expect(kcal, closeTo(2000, 15));
    }
  });

  test('su hedefi ve adım günlük toplamı', () {
    expect(waterGoalMl(70), 2250);
    expect(waterGoalMl(30), 1500);
    expect(waterGoalMl(200), 4000);
    var r = dailySteps(counter: 5000, base: null, carried: 0, lastToday: 0);
    expect(r.today, 0);
    r = dailySteps(counter: 6200, base: r.base, carried: r.carried, lastToday: r.today);
    expect(r.today, 1200);
    // Cihaz yeniden başladı: sayaç sıfırdan.
    r = dailySteps(counter: 300, base: r.base, carried: r.carried, lastToday: r.today);
    expect(r.today, 1500);
    r = dailySteps(counter: 500, base: r.base, carried: r.carried, lastToday: r.today);
    expect(r.today, 1700);
    expect(stepsKm(10000, 170), closeTo(7.04, 0.01));
  });

  test('oruç planları 20 saati aşmaz', () {
    expect(kFastPlans.every((h) => h <= kMaxFastHours), isTrue);
    final s = DateTime(2026, 1, 1, 20);
    expect(fastProgress(s, DateTime(2026, 1, 2, 4), 16), closeTo(0.5, 1e-9));
    expect(fastProgress(s, DateTime(2026, 1, 3), 48), 1.0);
  });

  test('uyku süresi, saat biçimi, hatırlatma anları', () {
    expect(sleepMinutes(23 * 60, 7 * 60), 480);
    expect(sleepMinutes(1 * 60, 8 * 60 + 30), 450);
    expect(clock(65), '01:05');
    expect(clock(3725), '1:02:05');
    expect(reminderSlots(9 * 60, 12 * 60, 60), [540, 600, 660]);
    expect(reminderSlots(22 * 60, 1 * 60, 60), [1320, 1380, 0]);
    expect(reminderSlots(0, 24 * 60, 1).length, 24);
  });

  test('aralıklı antrenman evreleri', () {
    final p = buildIntervals(work: 20, rest: 10, rounds: 8, prep: 10);
    expect(p.length, 1 + 8 + 7);
    expect(totalSeconds(p), 10 + 8 * 20 + 7 * 10);
    expect(phaseAt(p, 0)!.index, 0);
    expect(phaseAt(p, 10)!.index, 1);
    expect(phaseAt(p, 29)!.left, 1);
    expect(phaseAt(p, totalSeconds(p)), isNull);
  });

  test('satranç saati: artırma, gecikme, bayrak', () {
    final c = ChessClock(baseMs: 60000, incMs: 2000);
    c.press(0, 0); // beyaz başlatır, sıra siyahta (1)
    expect(c.active, 1);
    c.press(1, 10000);
    expect(c.remaining(1, 10000), 52000);
    expect(c.active, 0);
    c.press(0, 15000);
    expect(c.remaining(0, 15000), 57000);
    final d = ChessClock(baseMs: 10000, delayMs: 3000);
    d.press(1, 0); // sıra 0'da
    expect(d.remaining(0, 2000), 10000);
    expect(d.remaining(0, 5000), 8000);
    expect(d.check(20000), isTrue);
    expect(d.flagged, 0);
  });

  test('turnuva: lig fikstürü, eleme, puan tablosu', () {
    for (final n in [2, 3, 4, 5, 8]) {
      final r = roundRobin(n);
      final pairs = <String>{};
      for (final round in r) {
        final seen = <int>{};
        for (final g in round) {
          expect(seen.add(g.$1) && seen.add(g.$2), isTrue);
          pairs.add('${math.min(g.$1, g.$2)}-${math.max(g.$1, g.$2)}');
        }
      }
      expect(pairs.length, n * (n - 1) ~/ 2, reason: '$n');
    }
    final k = knockoutFirstRound(5);
    expect(k.length, 4);
    expect(k.where((g) => g.$2 == -1).length, 3);
    final t = standings(3, [(0, 1, 2, 0), (1, 2, 1, 1), (2, 0, 0, 3)]);
    expect(t.first.team, 0);
    expect(t.first.points, 6);
    expect(t[1].points, 1);
  });

  test('GPS mesafe ve tempo', () {
    expect(haversine(41, 29, 42, 29), closeTo(111195, 200));
    expect(routeLength([(41.0, 29.0), (41.0, 29.0), (41.001, 29.0)]), closeTo(111.2, 0.5));
    expect(pace(300, 1000), '5:00');
    expect(pace(10, 1), '–');
    final xy = projectRoute([(41.0, 29.0), (41.01, 29.01)], 100, 100);
    expect(xy.length, 2);
  });

  test('ağırlık: tek tekrar maksimumu ve hacim', () {
    expect(oneRepMax(100, 1), 100);
    expect(oneRepMax(100, 10), closeTo(133.33, 0.01));
    expect(volume([(50, 10), (60, 8)]), 980);
  });

  test('nabız tahmini sentetik sinyalde doğru', () {
    const fps = 30.0;
    final sig = [
      for (var i = 0; i < 20 * fps; i++) 120 + 3 * math.sin(2 * math.pi * 1.2 * i / fps) + 0.02 * i,
    ];
    expect(estimateBpm(sig, fps), closeTo(72, 3));
    expect(estimateBpm([for (var i = 0; i < 300; i++) 100.0], fps), isNull);
    expect(estimateBpm([1, 2, 3], fps), isNull);
  });

  test('işitme ve görme yardımcıları', () {
    expect(hearingLevels().length, 10);
    expect(hearingScore(null), 0);
    expect(hearingScore(0), 9);
    expect(hearingScore(9), 0);
    final plate = dotPlate(8, 42);
    expect(plate.length, greaterThan(200));
    expect(plate.where((d) => d.$4).length, greaterThan(30));
    expect(dotPlate(8, 42).first, plate.first); // tekrarlanabilir
    expect(kRingSizes.length, 10);
  });

  test('sigara: içilmeyen ve biriken', () {
    final r = smokeFree(DateTime(2026, 1, 1), DateTime(2026, 1, 11), 20, 100, 20);
    expect(r.cigarettes, 200);
    expect(r.money, 1000);
    expect(smokeFree(DateTime(2026, 2, 1), DateTime(2026, 1, 1), 20, 100, 20).cigarettes, 0);
  });

  test('ruh hali: kriz sözcükleri ve acil numaralar', () {
    expect(mentionsCrisis('Bugün çok yorgunum'), isFalse);
    expect(mentionsCrisis('I want to die'), isTrue);
    expect(mentionsCrisis('Kendime zarar vermek istiyorum'), isTrue);
    expect(emergencyNumber('TR'), '112');
    expect(emergencyNumber('US'), '911');
    expect(kHelplines['US'], '988');
  });

  test('seri, CSV, birimler', () {
    final today = DateTime(2026, 11, 25);
    expect(streak(['2026-11-25', '2026-11-24', '2026-11-22'], today), 2);
    expect(streak(['2026-11-24', '2026-11-23'], today), 2);
    expect(streak(<String>[], today), 0);
    expect(csvRow(['a', 'b,c', 'say "hi"', null]), 'a,"b,c","say ""hi""",');
    expect(mgdlToMmol(180), 10);
    expect(inRange(120, null, 130), isTrue);
    expect(inRange(140, null, 130), isFalse);
  });

  test('besin tablosu makul', () {
    expect(kFoods.length, greaterThanOrEqualTo(40));
    expect(kFoods.map((f) => f.key).toSet().length, kFoods.length);
    for (final f in kFoods) {
      expect(f.kcal, greaterThan(0), reason: f.key);
      expect(f.protein + f.carbs + f.fat, lessThanOrEqualTo(101), reason: f.key);
      final atwater = f.protein * 4 + f.carbs * 4 + f.fat * 9;
      expect((atwater - f.kcal).abs() / f.kcal, lessThan(0.35), reason: f.key); // lif payı
    }
    expect(foodByKey('apple')!.per(200).kcal, 104);
  });

  test('rutinler ve egzersiz çizimleri tutarlı', () {
    for (final r in [...kWorkouts, ...kStretches, ...kYoga]) {
      for (final s in r.steps) {
        expect(kExercises.any((e) => e.key == s.$1), isTrue, reason: s.$1);
      }
    }
    for (final e in kExercises) {
      expect(e.a.length, 22, reason: e.key);
      if (e.b != null) expect(e.b!.length, 22, reason: e.key);
    }
  });

  test('30 gün meydan okuma planı', () {
    final c = kChallenges.firstWhere((c) => c.key == 'c_squat');
    expect(challengeRest(4), isTrue);
    expect(challengeRest(5), isFalse);
    expect(challengeTarget(c, 4, 1), 0);
    expect(challengeTarget(c, 1, 1), 15);
    expect(challengeTarget(c, 30, 1), 100);
    expect(challengeTarget(c, 30, 0), 60);
    expect(challengeTarget(c, 30, 2), 140);
    // Artış tekdüze: dinlenme dışı günlerde hedef hiç azalmaz.
    var last = 0;
    for (var d = 1; d <= kChallengeDays; d++) {
      final v = challengeTarget(c, d, 1);
      if (v == 0) continue;
      expect(v, greaterThanOrEqualTo(last));
      last = v;
    }
    final p = kChallenges.firstWhere((c) => c.secs);
    expect(challengeTarget(p, 2, 1) % 5, 0);
    expect(challengeTotal(c, 1), greaterThan(1000));
    for (final ch in kChallenges) {
      expect(kExercises.any((e) => e.key == ch.exercise), isTrue, reason: ch.key);
    }
  });

  test('kafein: yarılanma, gün toplamı', () {
    final t0 = DateTime(2026, 11, 25, 8);
    final e = [(t0, 200.0)];
    expect(caffeineAt(e, t0), closeTo(200, 1e-9));
    expect(caffeineAt(e, t0.add(const Duration(hours: 5))), closeTo(100, 1e-6));
    expect(caffeineAt(e, t0.add(const Duration(hours: 10)), halfLifeHours: 5), closeTo(50, 1e-6));
    expect(caffeineAt(e, t0.subtract(const Duration(hours: 1))), 0);
    final below = caffeineBelow(e, t0, 50)!;
    expect(below.difference(t0).inMinutes, closeTo(600, 10));
    final by = caffeineByDay([(t0, 95.0), (t0.add(const Duration(hours: 3)), 63.0), (t0.add(const Duration(days: 1)), 47.0)]);
    expect(by['2026-11-25'], 158);
    expect(by['2026-11-26'], 47);
    expect(kDrinks.every((d) => d.mg >= 0 && d.size > 0), isTrue);
  });

  test('yürüyüş: tırmanış, rotaya uzaklık, GPX', () {
    final (g, l) = elevationGainLoss([100, 101, 102, 104, 103, 110, 108, 104, 100]);
    expect(g, closeTo(10, 1e-9));
    expect(l, closeTo(10, 1e-9));
    expect(elevationGainLoss([100, 101, 100, 101]).$1, 0);
    final route = [(41.0, 29.0), (41.0, 29.01)];
    final (off, along) = routeProgress(route, 41.0009, 29.005);
    expect(off, closeTo(100, 2));
    expect(along, closeTo(routeLength(route) / 2, 3));
    final gpx = toGpx('Sahil <yolu>', [(41.0, 29.0, 12.5, 0), (41.001, 29.001, null, null)]);
    expect(gpx, contains('<gpx version="1.1"'));
    expect(gpx, contains('Sahil &lt;yolu&gt;'));
    expect(gpx, contains('<ele>12.5</ele>'));
    expect(RegExp('<trkpt').allMatches(gpx).length, 2);
  });

  for (final id in [
    'uyg-vucut-kitle-indeksi', 'uyg-su-icme-hatirlatici', 'uyg-kalori-sayaci', 'uyg-makro-besin-hesaplayici',
    'uyg-kilo-takibi', 'uyg-antrenman-zamanlayici', 'uyg-ev-egzersiz-programi', 'uyg-yoga-akislari',
    'uyg-satranc-saati', 'uyg-turnuva-fiksturu', 'uyg-ruh-hali-gunlugu', 'uyg-sukur-gunlugu', 'uyg-ruya-gunlugu',
    'uyg-sigara-birakma', 'uyg-uyku-gunlugu', 'uyg-tansiyon-ve-seker-gunlugu', 'uyg-gorme-ve-renk-korlugu-testi',
    'uyg-aralikli-oruc-takibi', 'uyg-30-gun-meydan-okuma', 'uyg-kafein-takibi', 'uyg-yuruyus-rotalari',
  ]) {
    testWidgets('araç ekranı açılır: $id', (tester) async {
      final s = AppServices(hubId: 'm', backend: MemoryBackend(), ads: NoAdsService(), purchases: NoPurchaseService());
      final tool = saglikTool(id);
      final ctx = ToolContext(toolId: id, lang: 'tr', store: s.storeFor(id), services: s);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AppLook(style: saglikHubStyle, child: Scaffold(body: Builder(builder: (c) => tool.builder(c, ctx)))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('çocuk diş fırçalama aracı geçiş reklamını susturur (Families)', (tester) async {
    const id = 'uyg-dis-fircalama-zamanlayici';
    final s = AppServices(hubId: 'm', backend: MemoryBackend(), ads: NoAdsService(), purchases: NoPurchaseService());
    final before = DateTime.now().millisecondsSinceEpoch;
    final ctx = ToolContext(toolId: id, lang: 'tr', store: s.storeFor(id), services: s);
    await tester.pumpWidget(MaterialApp(
      home: AppLook(style: saglikHubStyle, child: Scaffold(body: Builder(builder: (c) => saglikTool(id).builder(c, ctx)))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(s.lastInterstitialMs, greaterThanOrEqualTo(before));
    expect(s.interstitialAllowed(DateTime.now().millisecondsSinceEpoch + 60000), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

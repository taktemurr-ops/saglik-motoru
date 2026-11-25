/// Sağlık ve Spor araçlarının saf (Flutter'sız) hesapları. Hepsi test
/// edilir; hiçbiri teşhis ya da tedavi önermez.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------- beden

/// Vücut kitle indeksi (kg / m²).
double bmi(double kg, double cm) {
  final m = cm / 100;
  if (kg <= 0 || m <= 0) return 0;
  return kg / (m * m);
}

/// Yetişkin VKİ sınıfı (DSÖ eşikleri): 0 zayıf, 1 normal, 2 fazla, 3 obez.
int bmiClass(double v) {
  if (v < 18.5) return 0;
  if (v < 25) return 1;
  if (v < 30) return 2;
  return 3;
}

/// Boya göre sağlıklı aralığın alt sınırı (VKİ 18,5).
double minHealthyWeight(double cm) => 18.5 * math.pow(cm / 100, 2).toDouble();

/// Hedef kilo: sağlıklı aralığın altına inilmez.
({double target, bool raised}) safeTargetWeight(double wanted, double cm) {
  final floor = (minHealthyWeight(cm) * 10).ceilToDouble() / 10;
  if (wanted < floor) return (target: floor, raised: true);
  return (target: wanted, raised: false);
}

/// Haftalık değişim çok hızlı mı? (haftada vücut ağırlığının %1'inden fazla)
bool tooFastChange(double kgPerWeek, double weight) => weight > 0 && kgPerWeek.abs() > weight * 0.01;

/// Son kayıtlardan haftalık eğilim (kg/hafta, en küçük kareler).
double weeklyTrend(List<(DateTime, double)> points) {
  if (points.length < 2) return 0;
  final t0 = points.first.$1;
  final xs = [for (final p in points) p.$1.difference(t0).inHours / 24.0];
  final ys = [for (final p in points) p.$2];
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den < 1e-9) return 0;
  return num / den * 7;
}

// ------------------------------------------------------------- enerji

/// Etkinlik katsayıları: az, hafif, orta, yüksek, çok yüksek.
const List<double> kActivity = [1.2, 1.375, 1.55, 1.725, 1.9];

/// Mifflin-St Jeor dinlenme enerjisi (kcal/gün).
double bmr({required double kg, required double cm, required int age, required bool male}) =>
    10 * kg + 6.25 * cm - 5 * age + (male ? 5 : -161);

/// Günlük enerji tahmini.
double tdee({required double kg, required double cm, required int age, required bool male, required int activity}) =>
    bmr(kg: kg, cm: cm, age: age, male: male) * kActivity[activity.clamp(0, kActivity.length - 1)];

/// Uygulamanın asla altına inmediği günlük kalori hedefi (yeme bozukluğu
/// riskine karşı; çok düşük kalorili planlar ancak hekim gözetiminde).
int calorieFloor(bool male) => male ? 1500 : 1200;

/// Hedefe göre günlük kalori: −1 ver, 0 koru, +1 al. Açık %20 ile
/// sınırlıdır ve [calorieFloor]'un altına inmez.
({int kcal, bool clamped}) calorieGoal(double tdeeKcal, int goal, bool male) {
  final raw = switch (goal) { -1 => tdeeKcal * 0.8, 1 => tdeeKcal * 1.1, _ => tdeeKcal };
  final floor = calorieFloor(male);
  if (raw < floor) return (kcal: floor, clamped: true);
  return (kcal: (raw / 10).round() * 10, clamped: false);
}

/// Kullanıcının elle girdiği hedef: alt sınırın altındaysa yükseltilir.
({int kcal, bool clamped}) clampCalorieGoal(int wanted, bool male) {
  final floor = calorieFloor(male);
  return wanted < floor ? (kcal: floor, clamped: true) : (kcal: wanted, clamped: false);
}

/// Makro dağılımı (yüzde: protein, karbonhidrat, yağ).
const List<(int, int, int)> kMacroSplits = [(25, 50, 25), (30, 40, 30), (30, 25, 45)];

/// Kaloriden gram: protein ve karbonhidrat 4, yağ 9 kcal/g.
({int protein, int carbs, int fat}) macroGrams(int kcal, (int, int, int) split) => (
      protein: (kcal * split.$1 / 100 / 4).round(),
      carbs: (kcal * split.$2 / 100 / 4).round(),
      fat: (kcal * split.$3 / 100 / 9).round(),
    );

/// Günlük su hedefi önerisi: kg başına 33 ml, 1,5–4 L arasında, 250'ye yuvarlı.
int waterGoalMl(double kg) {
  final v = (kg * 33).clamp(1500, 4000).toDouble();
  return (v / 250).round() * 250;
}

/// Adımdan yaklaşık mesafe (km) ve enerji (kcal).
double stepsKm(int steps, double cm) => steps * cm * 0.414 / 100000;
double stepsKcal(int steps, double kg) => steps * kg * 0.0005;

/// Adım sayacı cihaz açılışından beri birikir. Günün tabanı saklanır;
/// cihaz yeniden başlayınca sayaç sıfırdan başlar, önceki adımlar korunur.
({int today, int base, int carried}) dailySteps(
    {required int counter, required int? base, required int carried, required int lastToday}) {
  if (base == null) return (today: carried, base: counter, carried: carried);
  if (counter < base) return (today: lastToday + counter, base: 0, carried: lastToday);
  return (today: carried + counter - base, base: base, carried: carried);
}

// ------------------------------------------------------------- oruç

/// Desteklenen planlar (oruç saati). 20 saatten uzun oruç sunulmaz.
const List<int> kFastPlans = [12, 14, 16, 18, 20];
const int kMaxFastHours = 20;

/// Oruç ilerlemesi 0..1; plan bitince 1.
double fastProgress(DateTime start, DateTime now, int hours) {
  final h = hours.clamp(1, kMaxFastHours);
  final p = now.difference(start).inSeconds / (h * 3600);
  return p.clamp(0.0, 1.0);
}

// ------------------------------------------------------------ zaman

/// İki saat arasındaki uyku süresi (dakika); gece yarısını aşabilir.
int sleepMinutes(int bedMin, int wakeMin) {
  var d = wakeMin - bedMin;
  if (d <= 0) d += 24 * 60;
  return d;
}

/// "s:dd" ya da "dd:ss" biçimi.
String clock(int totalSeconds, {bool hours = false}) {
  final s = totalSeconds.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  if (hours || s >= 3600) return '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
  return '${two(s ~/ 60)}:${two(s % 60)}';
}

/// Belirli aralıkla [from, to) saatleri arasında hatırlatma anları
/// (dakika cinsinden gün içi). En fazla [max] tane.
List<int> reminderSlots(int fromMin, int toMin, int everyMin, {int max = 24}) {
  if (everyMin < 5) everyMin = 5;
  final out = <int>[];
  var end = toMin;
  if (end <= fromMin) end += 24 * 60;
  for (var m = fromMin; m < end && out.length < max; m += everyMin) {
    out.add(m % (24 * 60));
  }
  return out;
}

/// Bir sonraki gün-içi dakikanın tarihi (şu andan sonra).
DateTime nextAt(DateTime now, int minuteOfDay, {int addDays = 0}) {
  var d = DateTime(now.year, now.month, now.day, minuteOfDay ~/ 60, minuteOfDay % 60).add(Duration(days: addDays));
  if (addDays == 0 && !d.isAfter(now)) d = d.add(const Duration(days: 1));
  return d;
}

// ------------------------------------------------------- aralıklı antrenman

/// Antrenman evresi: 0 hazırlan, 1 çalış, 2 dinlen.
class Phase {
  final int kind;
  final int seconds;
  final int round;
  final String? label;
  const Phase(this.kind, this.seconds, this.round, [this.label]);
}

/// HIIT planı: hazırlık, sonra her tur çalışma + dinlenme (son dinlenme yok).
List<Phase> buildIntervals({required int work, required int rest, required int rounds, int prep = 10}) {
  final out = <Phase>[];
  if (prep > 0) out.add(Phase(0, prep, 0));
  for (var r = 1; r <= rounds; r++) {
    out.add(Phase(1, work, r));
    if (r < rounds && rest > 0) out.add(Phase(2, rest, r));
  }
  return out;
}

int totalSeconds(List<Phase> p) => p.fold(0, (a, b) => a + b.seconds);

/// Geçen süreye göre evre ve evrede kalan saniye; bitince null.
({int index, int left})? phaseAt(List<Phase> p, int elapsed) {
  var t = elapsed;
  for (var i = 0; i < p.length; i++) {
    if (t < p[i].seconds) return (index: i, left: p[i].seconds - t);
    t -= p[i].seconds;
  }
  return null;
}

// ------------------------------------------------------------- satranç

/// Satranç saati. Zamanlar milisaniye; [nowMs] dışarıdan verilir (test).
class ChessClock {
  final int baseMs;
  final int incMs;
  final int delayMs;
  final List<int> left;
  final List<int> moves = [0, 0];
  int? active; // sırası olan oyuncu
  int _turnStart = 0;
  int? flagged;

  ChessClock({required this.baseMs, this.incMs = 0, this.delayMs = 0}) : left = [baseMs, baseMs];

  /// Oyuncunun o anki kalan süresi.
  int remaining(int p, int nowMs) {
    if (active != p) return left[p];
    final used = math.max<int>(0, nowMs - _turnStart - delayMs);
    return math.max<int>(0, left[p] - used);
  }

  /// [p] oyuncusu saatine bastı: sıra rakibe geçer.
  void press(int p, int nowMs) {
    if (flagged != null) return;
    if (active == null) {
      active = 1 - p;
      _turnStart = nowMs;
      return;
    }
    if (active != p) return;
    final r = remaining(p, nowMs);
    if (r <= 0) {
      flagged = p;
      left[p] = 0;
      return;
    }
    left[p] = r + incMs;
    moves[p]++;
    active = 1 - p;
    _turnStart = nowMs;
  }

  /// Süre bitti mi? (bitince bayrak düşer)
  bool check(int nowMs) {
    final a = active;
    if (a != null && flagged == null && remaining(a, nowMs) <= 0) {
      flagged = a;
      left[a] = 0;
    }
    return flagged != null;
  }

  void pause(int nowMs) {
    final a = active;
    if (a == null || flagged != null) return;
    left[a] = remaining(a, nowMs);
    active = null;
  }
}

// ------------------------------------------------------------ turnuva

/// Lig fikstürü (daire yöntemi). Tek sayıda takımda -1 "bay"dır.
List<List<(int, int)>> roundRobin(int n) {
  if (n < 2) return [];
  final ids = [for (var i = 0; i < n; i++) i];
  if (n.isOdd) ids.add(-1);
  final m = ids.length;
  final rounds = <List<(int, int)>>[];
  var arr = List<int>.of(ids);
  for (var r = 0; r < m - 1; r++) {
    final games = <(int, int)>[];
    for (var i = 0; i < m ~/ 2; i++) {
      final a = arr[i], b = arr[m - 1 - i];
      if (a == -1 || b == -1) continue;
      games.add(r.isEven ? (a, b) : (b, a));
    }
    rounds.add(games);
    arr = [arr.first, arr.last, ...arr.sublist(1, m - 1)];
  }
  return rounds;
}

/// Eleme tablosunun ilk turu: 2'nin kuvvetine tamamlanır; boşluklar (-1)
/// en üst sıradaki katılımcılara "bay" verir.
List<(int, int)> knockoutFirstRound(int n) {
  if (n < 2) return [];
  var size = 1;
  while (size < n) {
    size *= 2;
  }
  final byes = size - n;
  final out = <(int, int)>[];
  var next = 0;
  for (var i = 0; i < size ~/ 2; i++) {
    if (i < byes) {
      out.add((next++, -1));
    } else {
      out.add((next++, next++));
    }
  }
  return out;
}

/// Lig puan tablosu satırı.
class StandRow {
  final int team;
  int played = 0, won = 0, drawn = 0, lost = 0, gf = 0, ga = 0;
  StandRow(this.team);
  int get points => won * 3 + drawn;
  int get diff => gf - ga;
}

/// Sonuçlardan puan tablosu (galibiyet 3, beraberlik 1).
List<StandRow> standings(int n, List<(int, int, int, int)> results) {
  final rows = [for (var i = 0; i < n; i++) StandRow(i)];
  for (final r in results) {
    final a = rows[r.$1], b = rows[r.$2];
    a.played++;
    b.played++;
    a.gf += r.$3;
    a.ga += r.$4;
    b.gf += r.$4;
    b.ga += r.$3;
    if (r.$3 > r.$4) {
      a.won++;
      b.lost++;
    } else if (r.$3 < r.$4) {
      b.won++;
      a.lost++;
    } else {
      a.drawn++;
      b.drawn++;
    }
  }
  rows.sort((x, y) {
    final c = y.points.compareTo(x.points);
    if (c != 0) return c;
    final d = y.diff.compareTo(x.diff);
    if (d != 0) return d;
    return y.gf.compareTo(x.gf);
  });
  return rows;
}

// --------------------------------------------------------------- GPS

/// Büyük daire mesafesi (m).
double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min<double>(1, math.sqrt(a)));
}

/// Rota uzunluğu; doğruluğu kötü ya da sıçrayan noktalar atlanır.
double routeLength(List<(double, double)> pts, {double minStep = 2}) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final s = haversine(pts[i - 1].$1, pts[i - 1].$2, pts[i].$1, pts[i].$2);
    if (s >= minStep) d += s;
  }
  return d;
}

/// Tempo (dakika/km) metni; mesafe yoksa "–".
String pace(int seconds, double meters) {
  if (meters < 10 || seconds <= 0) return '–';
  final spk = seconds / (meters / 1000);
  final m = spk ~/ 60, s = (spk % 60).round();
  if (m > 59) return '–';
  return '$m:${(s == 60 ? 0 : s).toString().padLeft(2, '0')}';
}

/// Noktaları [w]×[h] kutuya yerleştirir (eşit ölçek).
List<(double, double)> projectRoute(List<(double, double)> pts, double w, double h) {
  if (pts.isEmpty) return [];
  var minLat = pts.first.$1, maxLat = minLat, minLon = pts.first.$2, maxLon = minLon;
  for (final p in pts) {
    minLat = math.min(minLat, p.$1);
    maxLat = math.max(maxLat, p.$1);
    minLon = math.min(minLon, p.$2);
    maxLon = math.max(maxLon, p.$2);
  }
  final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  final spanX = math.max(1e-9, (maxLon - minLon) * k), spanY = math.max(1e-9, maxLat - minLat);
  final sc = math.min(w / spanX, h / spanY);
  final ox = (w - spanX * sc) / 2, oy = (h - spanY * sc) / 2;
  return [for (final p in pts) (ox + (p.$2 - minLon) * k * sc, h - oy - (p.$1 - minLat) * sc)];
}

// ------------------------------------------------------------ ağırlık

/// Tahmini tek tekrar maksimumu (Epley).
double oneRepMax(double kg, int reps) => reps <= 1 ? kg : kg * (1 + reps / 30);

/// Set hacmi toplamı (kg × tekrar).
double volume(List<(double, int)> sets) => sets.fold(0.0, (a, s) => a + s.$1 * s.$2);

// ---------------------------------------------------------- nabız (PPG)

/// Kırmızı kanal ortalamalarından nabız tahmini (atım/dk). [fps] örnekleme
/// hızı. Hareketli ortalamayla trend çıkarılır, tepe sayılır. Güvenilmezse null.
double? estimateBpm(List<double> red, double fps) {
  if (fps <= 0 || red.length < fps * 5) return null;
  List<double> smooth(List<double> x, int w) {
    final out = List<double>.filled(x.length, 0);
    var acc = 0.0;
    for (var i = 0; i < x.length; i++) {
      acc += x[i];
      if (i >= w) acc -= x[i - w];
      out[i] = acc / math.min<int>(i + 1, w);
    }
    return out;
  }

  final trend = smooth(red, math.max<int>(3, (fps * 1.0).round()));
  final hp = [for (var i = 0; i < red.length; i++) red[i] - trend[i]];
  final sig = smooth(hp, math.max<int>(1, (fps * 0.1).round()));
  final start = (fps * 1.0).round();
  final minGap = (fps * 60 / 200).round(); // en fazla 200 atım/dk
  final peaks = <int>[];
  for (var i = math.max<int>(start, 1); i < sig.length - 1; i++) {
    if (sig[i] > 0 && sig[i] >= sig[i - 1] && sig[i] > sig[i + 1]) {
      if (peaks.isEmpty || i - peaks.last >= minGap) peaks.add(i);
    }
  }
  if (peaks.length < 4) return null;
  final gaps = [for (var i = 1; i < peaks.length; i++) (peaks[i] - peaks[i - 1]).toDouble()]..sort();
  final med = gaps[gaps.length ~/ 2];
  final bpm = 60 * fps / med;
  if (bpm < 40 || bpm > 200) return null;
  return bpm;
}

// ------------------------------------------------------------ işitme

/// Test edilen frekanslar (Hz).
const List<int> kHearingFreqs = [250, 500, 1000, 2000, 4000, 8000];

/// Ses seviyesi adımları (0..1); her adım yaklaşık 6 dB.
List<double> hearingLevels() => [for (var i = 9; i >= 0; i--) math.pow(0.5, i).toDouble()];

/// Göreli puan: duyulan ilk seviye ne kadar düşükse puan o kadar yüksek
/// (0..9). Duyulmadıysa 0. Bu bir dB HL değeri DEĞİLDİR.
int hearingScore(int? heardLevelIndex) => heardLevelIndex == null ? 0 : 9 - heardLevelIndex.clamp(0, 9);

// ------------------------------------------------------------ görme

/// Halka (Landolt C) testi satırları: boşluk açısı ve göreli boyut.
/// Boyutlar yalnızca karşılaştırma içindir; gerçek görme keskinliği değildir.
const List<double> kRingSizes = [1.0, 0.8, 0.63, 0.5, 0.4, 0.32, 0.25, 0.2, 0.16, 0.125];

/// Basit bir sözde rastgele üreteç (tekrarlanabilir desenler için).
class Lcg {
  int _s;
  Lcg(int seed) : _s = seed & 0x7fffffff;
  int next() => _s = (_s * 1103515245 + 12345) & 0x7fffffff;
  double unit() => next() / 0x7fffffff;
  int below(int n) => next() % n;
}

/// 5×7 rakam bitmapleri (özgün, basit yazı).
const List<List<String>> kDigits = [
  ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  ['11110', '00001', '00001', '01110', '00001', '00001', '11110'],
  ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
];

/// Nokta deseni: (x, y, yarıçap, rakama ait mi) — 0..1 birim karede.
List<(double, double, double, bool)> dotPlate(int digit, int seed, {int count = 420}) {
  final rnd = Lcg(seed);
  final out = <(double, double, double, bool)>[];
  final rows = kDigits[digit % 10];
  var tries = 0;
  while (out.length < count && tries < count * 30) {
    tries++;
    final r = 0.012 + rnd.unit() * 0.018;
    final x = rnd.unit(), y = rnd.unit();
    final dx = x - 0.5, dy = y - 0.5;
    if (dx * dx + dy * dy > (0.5 - r) * (0.5 - r)) continue;
    var ok = true;
    for (final o in out) {
      final ex = o.$1 - x, ey = o.$2 - y;
      if (ex * ex + ey * ey < (o.$3 + r + 0.003) * (o.$3 + r + 0.003)) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    // Rakam alanı: kutu 0.25..0.75 × 0.18..0.82
    final gx = ((x - 0.25) / 0.5 * 5).floor(), gy = ((y - 0.18) / 0.64 * 7).floor();
    final inDigit = gx >= 0 && gx < 5 && gy >= 0 && gy < 7 && rows[gy][gx] == '1';
    out.add((x, y, r, inDigit));
  }
  return out;
}

// ------------------------------------------------------------ sigara

/// Bırakıştan beri içilmeyen sigara ve biriken para.
({int cigarettes, double money}) smokeFree(DateTime quit, DateTime now, int perDay, double packPrice, int packSize) {
  if (now.isBefore(quit)) return (cigarettes: 0, money: 0);
  final days = now.difference(quit).inMinutes / (24 * 60);
  final c = (days * perDay).floor();
  final money = packSize <= 0 ? 0.0 : c / packSize * packPrice;
  return (cigarettes: c, money: money);
}

/// Genel bilgi kilometre taşları (dakika). Kişiden kişiye değişir.
const List<int> kQuitMilestones = [20, 12 * 60, 2 * 24 * 60, 14 * 24 * 60, 90 * 24 * 60, 365 * 24 * 60];

// ----------------------------------------------------------- ruh hali

/// Kriz sözcükleri (küçük harf, kısmi eşleşme). Yalnızca yardım bilgisini
/// öne çıkarmak için; hiçbir şey gönderilmez ya da saklanmaz.
const List<String> kCrisisWords = [
  'intihar', 'kendimi öldür', 'ölmek istiyorum', 'yaşamak istemiyorum', 'kendime zarar',
  'suicide', 'kill myself', 'want to die', 'end my life', 'self harm', 'self-harm', 'hurt myself',
  'selbstmord', 'suizid', 'mich umbringen', 'suicidio', 'matarme', 'quiero morir', 'suicide', 'me tuer',
  'انتحار', 'أقتل نفسي', 'خودکشی', 'התאבדות', 'خودکشی', 'суицид', 'покончить с собой', 'убить себя', 'самогубство',
  'samobój', 'sebevražd', 'sinucid', 'öngyilk', 'αυτοκτον', 'suicidio', 'suicídio', 'zelfmoord', 'självmord',
  'selvmord', 'itsemurha', '自殺', '死にたい', '자살', '죽고 싶', '自杀', '想死', 'आत्महत्या', 'আত্মহত্যা',
  'bunuh diri', 'membunuh diri', 'ฆ่าตัวตาย', 'tự tử', 'tự sát', 'magpakamatay',
];

bool mentionsCrisis(String text) {
  final s = text.toLowerCase();
  for (final w in kCrisisWords) {
    if (s.contains(w)) return true;
  }
  return false;
}

/// Ülkeye göre gizli ve ücretsiz destek hattı (yalnızca yaygın bilinenler);
/// diğerleri için uluslararası rehber gösterilir.
const Map<String, String> kHelplines = {
  'US': '988', 'CA': '988', 'GB': '116 123', 'IE': '116 123', 'AU': '13 11 14', 'NZ': '1737',
  'DE': '0800 111 0 111', 'FR': '3114', 'ES': '024', 'NL': '0800 0113',
};

/// Ülkenin acil numarası (bilinmiyorsa 112).
String emergencyNumber(String country) => switch (country) {
      'US' || 'CA' || 'MX' || 'PH' => '911',
      'GB' || 'IE' => '999',
      'AU' => '000',
      'NZ' => '111',
      'JP' || 'KR' || 'TW' => '119',
      'CN' => '120',
      'IN' => '112',
      'TH' => '1669',
      'VN' => '115',
      'ID' => '112',
      'MY' => '999',
      'BD' => '999',
      'PK' => '1122',
      'IR' => '115',
      'IL' => '101',
      'SA' || 'AE' => '997',
      'EG' => '123',
      _ => '112',
    };

// -------------------------------------------------------------- çeşitli

/// Arka arkaya gün sayısı (bugün ya da dün biten).
int streak(Iterable<String> isoDays, DateTime today) {
  final set = isoDays.toSet();
  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  var d = DateTime(today.year, today.month, today.day);
  if (!set.contains(iso(d))) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (set.contains(iso(d))) {
    n++;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

String isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

/// Kan şekeri birimi çevirisi (mg/dL ↔ mmol/L).
double mgdlToMmol(double v) => v / 18.0;
double mmolToMgdl(double v) => v * 18.0;

/// Değer kullanıcının kendi aralığında mı? (yorum değil, yalnız karşılaştırma)
bool inRange(double v, double? lo, double? hi) => (lo == null || v >= lo) && (hi == null || v <= hi);

/// Basit CSV satırı (virgül, tırnak ve satır sonu kaçışlı).
String csvRow(List<Object?> cells) => cells.map((c) {
      final s = '${c ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }).join(',');

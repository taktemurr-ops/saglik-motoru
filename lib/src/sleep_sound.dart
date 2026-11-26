/// Uyku sesi günlüğü: gece boyunca mikrofon düzeyini izler, ortam
/// gürültüsünün belirgin üstüne çıkan "ses olaylarını" (horlama, öksürük,
/// konuşma, dış ses…) zamanıyla kaydeder ve isteğe bağlı kısa ses kesitleri
/// çıkarır. Saf Dart, testli.
///
/// Esenlik günlüğüdür: sesin türünü sınıflandırmaz, horlama ya da uyku
/// apnesi gibi bir durumu tespit etmez veya teşhis koymaz.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Bir ses olayı. [at]: kayıt başından saniye, [dur]: saniye,
/// [peak]: ortam düzeyinin kaç dB üstüne çıktığı, [clip]: kesit dosyası adı.
class SoundEvent {
  final int at, dur;
  final double peak;
  final String clip;
  const SoundEvent(this.at, this.dur, this.peak, [this.clip = '']);

  SoundEvent withClip(String c) => SoundEvent(at, dur, peak, c);

  Map<String, Object?> toJson() => {'at': at, 'dur': dur, 'peak': (peak * 10).round() / 10, 'clip': clip};

  static SoundEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'], dur = j['dur'], peak = j['peak'];
    if (at is! num || dur is! num) return null;
    return SoundEvent(at.toInt(), dur.toInt(), peak is num ? peak.toDouble() : 0, j['clip'] is String ? j['clip'] as String : '');
  }
}

/// Bir gecenin kaydı.
class NightRecord {
  final String id;
  final DateTime start, end;
  final List<SoundEvent> events;

  /// Dakika başına en yüksek düzey (ortamın kaç dB üstü, 0..60).
  final List<int> levels;
  final List<int> factors;
  final String note;
  const NightRecord({
    required this.id,
    required this.start,
    required this.end,
    this.events = const [],
    this.levels = const [],
    this.factors = const [],
    this.note = '',
  });

  int get minutes => math.max(0, end.difference(start).inMinutes);

  /// Toplam sesli süre (saniye).
  int get soundSeconds => events.fold<int>(0, (a, e) => a + e.dur);

  /// Saat başına olay sayısı (yalnızca bilgi; tıbbi bir ölçüt değildir).
  double get perHour => minutes == 0 ? 0 : events.length / (minutes / 60);

  /// Gecenin sessiz geçen oranı (0..1).
  double get quietShare => minutes == 0 ? 1 : math.min(1.0, math.max(0.0, 1 - soundSeconds / (minutes * 60)));

  NightRecord copyWith({List<SoundEvent>? events, List<int>? factors, String? note}) => NightRecord(
        id: id,
        start: start,
        end: end,
        events: events ?? this.events,
        levels: levels,
        factors: factors ?? this.factors,
        note: note ?? this.note,
      );

  Map<String, Object?> toJson() => {
        'id': id, 'start': start.toIso8601String(), 'end': end.toIso8601String(),
        'events': [for (final e in events) e.toJson()], 'levels': levels, 'factors': factors, 'note': note,
      };

  static NightRecord? fromJson(Map<String, Object?> j) {
    final s = j['start'] is String ? DateTime.tryParse(j['start'] as String) : null;
    final e = j['end'] is String ? DateTime.tryParse(j['end'] as String) : null;
    if (j['id'] is! String || s == null || e == null) return null;
    return NightRecord(
      id: j['id'] as String,
      start: s,
      end: e,
      events: (j['events'] as List? ?? const []).map(SoundEvent.fromJson).whereType<SoundEvent>().toList(),
      levels: [for (final x in (j['levels'] as List? ?? const [])) if (x is num) math.min(60, math.max(0, x.toInt()))],
      factors: [for (final x in (j['factors'] as List? ?? const [])) if (x is num) x.toInt()],
      note: j['note'] is String ? j['note'] as String : '',
    );
  }
}

/// Gerçek zamanlı ses olayı bulucu. Mikrofon PCM16 örneklerini [add] ile
/// alır; yarım saniyelik pencerelerin düzeyini ortam düzeyiyle karşılaştırır.
class SoundDetector {
  final int rate;

  /// Ortam düzeyinin kaç dB üstü "olay" sayılır (düşük = daha hassas).
  final double threshold;

  /// Olaydan önce kesite eklenen saniye, kesitin en uzun süresi ve olayın
  /// bitmesi için gereken sessiz süre (saniye).
  final int preRoll, maxClip, hangover;

  /// Kesit hazır olduğunda (olay bitince) çağrılır.
  void Function(SoundEvent e, Int16List clip)? onEvent;

  SoundDetector({this.rate = 16000, this.threshold = 10, this.preRoll = 2, this.maxClip = 20, this.hangover = 3, this.onEvent});

  int get _win => rate ~/ 2;

  final List<SoundEvent> events = [];
  final List<int> levels = [];
  double? floor;

  final List<int> _buf = [];
  final List<Int16List> _pre = [];
  int _windows = 0;
  double _minuteMax = 0;
  int _minuteWins = 0;

  // olay durumu
  int? _evStart;
  int _evLast = 0;
  double _evPeak = 0;
  int _quiet = 0;
  final List<Int16List> _clip = [];

  /// Şu an bir olayın içinde mi?
  bool get active => _evStart != null;

  /// Kayıt süresi (saniye).
  double get seconds => _windows / 2;

  /// Bir pencerenin dBFS düzeyi.
  static double dbfs(Int16List w) {
    if (w.isEmpty) return -100;
    var sum = 0.0;
    for (final v in w) {
      sum += v * v;
    }
    final rms = math.sqrt(sum / w.length) / 32768.0;
    return math.max(-100.0, 20 * math.log(math.max(rms, 1e-7)) / math.ln10);
  }

  void add(Int16List samples) {
    _buf.addAll(samples);
    while (_buf.length >= _win) {
      final w = Int16List.fromList(_buf.sublist(0, _win));
      _buf.removeRange(0, _win);
      _window(w);
    }
  }

  void _window(Int16List w) {
    final db = dbfs(w);
    final f = floor ?? db;
    final above = db - f;
    final t = _windows; // pencere sırası (0,5 sn)
    _windows++;
    final loud = above >= threshold;
    if (loud) {
      if (_evStart == null) {
        _evStart = t;
        _evPeak = above;
        _clip
          ..clear()
          ..addAll(_pre);
      }
      _evLast = t;
      _evPeak = math.max(_evPeak, above);
      _quiet = 0;
    } else if (_evStart != null) {
      _quiet++;
    }
    if (_evStart != null && _clip.length < (preRoll + maxClip) * 2) _clip.add(w);
    if (_evStart != null && _quiet >= hangover * 2) _finish();
    if (_evStart != null && t - _evStart! >= 600) {
      // 5 dakikadan uzun kesintisiz ses (ör. vantilatör açıldı): olay kapanır,
      // yeni düzey ortam düzeyi kabul edilir.
      _finish();
      floor = db;
    } else if (_evStart == null) {
      // Ortam düzeyi: düşüşlere hemen, yükselişlere yavaşça uyar.
      floor = db < f ? db : f + (db - f) * 0.02;
    }
    _pre.add(w);
    while (_pre.length > preRoll * 2) {
      _pre.removeAt(0);
    }
    _minuteMax = math.max(_minuteMax, math.min(60.0, math.max(0.0, above)));
    _minuteWins++;
    if (_minuteWins >= 120) _flushMinute();
  }

  void _flushMinute() {
    levels.add(_minuteMax.round());
    _minuteMax = 0;
    _minuteWins = 0;
  }

  void _finish() {
    final s = _evStart!;
    final e = SoundEvent(s ~/ 2, math.max(1, ((_evLast - s + 1) / 2).ceil()), _evPeak);
    events.add(e);
    final pcm = Int16List(_clip.fold<int>(0, (a, w) => a + w.length));
    var o = 0;
    for (final w in _clip) {
      pcm.setAll(o, w);
      o += w.length;
    }
    _clip.clear();
    _evStart = null;
    _quiet = 0;
    onEvent?.call(e, pcm);
  }

  /// Kaydı bitirir: süren olayı ve yarım dakikayı kapatır.
  void close() {
    if (_evStart != null) _finish();
    if (_minuteWins > 0) _flushMinute();
  }
}

/// 16 bit mono PCM'den WAV dosyası.
Uint8List pcmToWav(Int16List pcm, int rate) {
  final data = pcm.length * 2;
  final b = ByteData(44 + data);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    b.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Bayt akışını (küçük sonlu PCM16) örneklere çevirir; tek kalan bayt
/// [carry] ile bir sonraki parçaya aktarılır.
Int16List pcmBytes(Uint8List data, List<int> carry) {
  final bytes = [...carry, ...data];
  carry.clear();
  if (bytes.length.isOdd) carry.add(bytes.removeLast());
  final bd = ByteData.sublistView(Uint8List.fromList(bytes));
  final out = Int16List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little);
  }
  return out;
}

/// Sağlık araçlarının ortak yardımcıları (Araç Kutusu motorundan kopyalandı
/// ve genişletildi): çeviri, liste düzeni, ses üretimi, kamera kutusu,
/// çöp-adam çizimi, rutin oynatıcı, hatırlatma ve ödüllü ekstra.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/app/studio_ui.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data.dart';
import 'logic.dart';
import 'platform/notify.dart';
import 'tx.dart';

/// Araç etiketi (33 dil).
String L(ToolContext t, String key) => t.t(kSaglikL[key] ?? [key]);

/// Yer tutuculu etiket: {n} gibi alanlar doldurulur.
String Lf(ToolContext t, String key, Map<String, Object> p) {
  var s = L(t, key);
  p.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Virgülle ayrılmış etiket listesi.
List<String> Ls(ToolContext t, String key) => L(t, key).split(',');

/// Aracın gövdesi: kaydırılabilir sütun.
class ToolList extends StatelessWidget {
  final List<Widget> children;
  const ToolList({super.key, required this.children});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: children);
}

/// "Bu cihazda yok" bilgisi.
Widget notAvailable(ToolContext t) =>
    AppInfoCard(t.tx(kIsWeb ? 'web_unavailable' : 'not_available'), icon: Icons.sensors_off_rounded);

/// Büyük sayı göstergesi.
class BigReadout extends StatelessWidget {
  final String value;
  final String unit;
  final String? caption;
  const BigReadout(this.value, {super.key, this.unit = '', this.caption});

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return AppPanel(
      child: Column(children: [
        if (caption != null) Text(caption!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: TextStyle(color: s.number, fontSize: 64, fontWeight: FontWeight.w900)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(unit, style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Seçenek düğmeleri (SegmentedButton) için kısa yol.
class Choice<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  const Choice({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});

  /// Onaylı tasarımın hap çipleri (seçili olan vurgu renginde).
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < values.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  widthFactor: 1,
                  child: StudioPill(
                    label: labels[i],
                    selected: values[i] == selected,
                    onTap: () => onChanged(values[i]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Açılır liste.
class Pick<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final String Function(T) text;
  final T value;
  final ValueChanged<T> onChanged;
  const Pick({
    super.key,
    required this.label,
    required this.values,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        dropdownColor: StudioLook.of(context).sheet,
        borderRadius: BorderRadius.circular(16),
        iconEnabledColor: StudioLook.of(context).accent,
        decoration: InputDecoration(
          labelText: label,
        ),
        items: [for (final v in values) DropdownMenuItem<T>(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Düz metin alanı.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.onChanged,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 17),
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }
}

/// Tarih seçme satırı.
class DateRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  const DateRow({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_rounded),
      title: Text(label),
      subtitle: Text(loc.formatFullDate(value)),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: first ?? DateTime(1800),
          lastDate: last ?? DateTime(2300),
        );
        if (d != null) onChanged(d);
      },
    );
  }
}

// ------------------------------------------------------------------ ses

/// 16 bit mono WAV üretir. [segments]: (frekans Hz, süre ms); frekans 0 sessizliktir.
Uint8List makeWav(List<(double, int)> segments, {int rate = 22050, double volume = 0.8, bool square = false}) {
  var total = 0;
  for (final s in segments) {
    total += (rate * s.$2 / 1000).round();
  }
  final data = ByteData(44 + total * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + total * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, total * 2, Endian.little);
  var o = 44;
  for (final s in segments) {
    final n = (rate * s.$2 / 1000).round();
    final fade = math.min<int>(n ~/ 2, (rate * 0.005).round());
    for (var i = 0; i < n; i++) {
      var v = 0.0;
      if (s.$1 > 0) {
        final ph = math.sin(2 * math.pi * s.$1 * i / rate);
        v = square ? (ph >= 0 ? 1.0 : -1.0) : ph;
        var env = 1.0;
        if (i < fade) env = i / fade;
        if (n - i < fade) env = (n - i) / fade;
        v *= env * volume;
      }
      data.setInt16(o, (v * 32767).round().clamp(-32768, 32767), Endian.little);
      o += 2;
    }
  }
  return data.buffer.asUint8List();
}

/// Tek bir ses çalar; kapanınca kaynakları bırakır.
class TonePlayer {
  final AudioPlayer _p = AudioPlayer();

  Future<void> play(Uint8List wav, {bool loop = false}) async {
    try {
      await _p.stop();
      await _p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _p.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (_) {/* ses yoksa sessiz geç */}
  }

  Future<void> stop() async {
    try {
      await _p.stop();
    } catch (_) {}
  }

  void dispose() {
    unawaited(_p.dispose());
  }
}

// --------------------------------------------------------------- kamera

/// İzin açıklaması bir kez gösterildi mi?
Future<bool> rationaleOnce(BuildContext context, ToolContext t, String perm, IconData icon) async {
  if (await t.store.readBool('perm.$perm')) return true;
  if (!context.mounted) return false;
  final ok = await explainPermission(context, lang: t.lang, icon: icon, reason: L(t, 'perm_$perm'));
  if (ok) await t.store.writeBool('perm.$perm', true);
  return ok;
}

/// Kamerayı açıp önizlemeyi çizen kutu. [builder] hazır denetleyiciyle
/// çağrılır; kamera yoksa ya da izin verilmezse bilgi gösterilir.
class CameraBox extends StatefulWidget {
  final ToolContext tool;
  final CameraLensDirection lens;
  final ResolutionPreset preset;
  final Widget Function(BuildContext context, CameraController c) builder;
  final void Function(CameraController c)? onReady;
  const CameraBox({
    super.key,
    required this.tool,
    required this.builder,
    this.lens = CameraLensDirection.back,
    this.preset = ResolutionPreset.medium,
    this.onReady,
  });

  @override
  State<CameraBox> createState() => _CameraBoxState();
}

class _CameraBoxState extends State<CameraBox> with WidgetsBindingObserver {
  CameraController? _c;
  String? _error;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!_asked) {
      _asked = true;
      final ok = await rationaleOnce(context, widget.tool, 'camera', Icons.photo_camera_rounded);
      if (!ok) {
        if (mounted) setState(() => _error = appTx('perm_denied', widget.tool.lang));
        return;
      }
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'none');
      final cam = cams.firstWhere((c) => c.lensDirection == widget.lens, orElse: () => cams.first);
      final c = CameraController(cam, widget.preset, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      widget.onReady?.call(c);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code.toLowerCase().contains('denied')
          ? appTx('perm_denied', widget.tool.lang)
          : appTx(kIsWeb ? 'web_unavailable' : 'not_available', widget.tool.lang));
    } catch (_) {
      if (mounted) setState(() => _error = appTx('not_available', widget.tool.lang));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _c = null;
      unawaited(c.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _error == null) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final c = _c;
    _c = null;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppInfoCard(_error!, icon: Icons.no_photography_rounded);
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    return widget.builder(context, c);
  }
}

/// Önizlemeyi kutuya sığdırır.
Widget cameraPreview(CameraController c, {double? height}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      height: height,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.previewSize?.height ?? 480,
          height: c.value.previewSize?.width ?? 640,
          child: CameraPreview(c),
        ),
      ),
    ),
  );
}

/// Kamera karesinden ortadaki rengi ve ortalama parlaklığı çıkarır.
/// Android YUV420 ve iOS BGRA8888 biçimlerini anlar.
({int r, int g, int b, double luma})? sampleFrame(CameraImage img) {
  try {
    final w = img.width, h = img.height;
    final cx = w ~/ 2, cy = h ~/ 2;
    if (img.format.group == ImageFormatGroup.bgra8888) {
      final p = img.planes.first;
      int px(int x, int y, int ch) => p.bytes[y * p.bytesPerRow + x * 4 + ch];
      var sum = 0.0, n = 0;
      for (var y = 0; y < h; y += h ~/ 16 + 1) {
        for (var x = 0; x < w; x += w ~/ 16 + 1) {
          sum += 0.299 * px(x, y, 2) + 0.587 * px(x, y, 1) + 0.114 * px(x, y, 0);
          n++;
        }
      }
      return (r: px(cx, cy, 2), g: px(cx, cy, 1), b: px(cx, cy, 0), luma: sum / math.max<int>(1, n));
    }
    final yp = img.planes[0];
    var sum = 0.0, n = 0;
    for (var y = 0; y < h; y += h ~/ 16 + 1) {
      for (var x = 0; x < w; x += w ~/ 16 + 1) {
        sum += yp.bytes[y * yp.bytesPerRow + x];
        n++;
      }
    }
    final yv = yp.bytes[cy * yp.bytesPerRow + cx].toDouble();
    var u = 128.0, v = 128.0;
    if (img.planes.length >= 3) {
      final up = img.planes[1], vp = img.planes[2];
      final ps = up.bytesPerPixel ?? 1;
      final ui = (cy ~/ 2) * up.bytesPerRow + (cx ~/ 2) * ps;
      final vi = (cy ~/ 2) * vp.bytesPerRow + (cx ~/ 2) * (vp.bytesPerPixel ?? 1);
      if (ui < up.bytes.length && vi < vp.bytes.length) {
        u = up.bytes[ui].toDouble();
        v = vp.bytes[vi].toDouble();
      }
    }
    int c(double x) => x.round().clamp(0, 255);
    return (
      r: c(yv + 1.402 * (v - 128)),
      g: c(yv - 0.344136 * (u - 128) - 0.714136 * (v - 128)),
      b: c(yv + 1.772 * (u - 128)),
      luma: sum / math.max<int>(1, n),
    );
  } catch (_) {
    return null;
  }
}

/// Basit çizgi grafik (son değerler).
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double? min;
  final double? max;
  final double height;
  const Sparkline(this.values, {super.key, this.min, this.max, this.height = 90});

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparkPainter(values, min, max, s.accent)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final double? lo, hi;
  final Color color;
  _SparkPainter(this.v, this.lo, this.hi, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final a = lo ?? v.reduce(math.min);
    var b = hi ?? v.reduce(math.max);
    if (b - a < 1e-9) b = a + 1;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height * (1 - ((v[i] - a) / (b - a)).clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

// ------------------------------------------------------------ sağlık ekleri

/// Tek kulak (sol/sağ) için stereo ton (16 bit WAV). [volume] 0..1.
Uint8List makeStereoTone(double freq, int ms, {required bool left, double volume = 0.5, int rate = 44100}) {
  final n = (rate * ms / 1000).round();
  final data = ByteData(44 + n * 4);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 4, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 4, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 4, Endian.little);
  final fade = math.min<int>(n ~/ 2, (rate * 0.02).round());
  for (var i = 0; i < n; i++) {
    var env = 1.0;
    if (i < fade) env = i / fade;
    if (n - i < fade) env = (n - i) / fade;
    final v = (math.sin(2 * math.pi * freq * i / rate) * env * volume * 32767).round().clamp(-32768, 32767);
    data.setInt16(44 + i * 4, left ? v : 0, Endian.little);
    data.setInt16(46 + i * 4, left ? 0 : v, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Kısa bip sesleri (evre geçişleri için).
final Uint8List beepShort = makeWav([(880, 120)], volume: 0.6);
final Uint8List beepLong = makeWav([(660, 160), (0, 60), (990, 320)], volume: 0.7);

/// Sayıyı kısa yazar (gereksiz ,0 olmadan).
String fmt(num v, [int digits = 1]) {
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String two(int v) => v.toString().padLeft(2, '0');

/// Gün içi dakikayı "ss:dd" yazar.
String hm(int minuteOfDay) => '${two(minuteOfDay ~/ 60 % 24)}:${two(minuteOfDay % 60)}';

/// Saat seçme satırı (gün içi dakika).
class TimeRow extends StatelessWidget {
  final String label;
  final int minute;
  final ValueChanged<int> onChanged;
  const TimeRow({super.key, required this.label, required this.minute, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule_rounded),
      title: Text(label),
      trailing: Text(hm(minute), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      onTap: () async {
        final r = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60));
        if (r != null) onChanged(r.hour * 60 + r.minute);
      },
    );
  }
}

/// Bölüm başlığı ve içeriği tek panelde.
class Section extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;
  const Section(this.title, {super.key, this.icon, required this.children});

  @override
  Widget build(BuildContext context) => AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppHeading(title, icon: icon),
          const SizedBox(height: 6),
          ...children,
        ]),
      );
}

/// Sayı alanından değer (boşsa null).
double? numOf(TextEditingController c) => parseNumber(c.text);

/// Kaydırıcı satırı.
class SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int? divisions;
  final String Function(double) text;
  final ValueChanged<double> onChanged;
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.text,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(flex: 4, child: Text(label)),
          Expanded(
            flex: 7,
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
          SizedBox(width: 72, child: Text(text(value), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      );
}

/// Ödüllü ekstra: Premium/reklamsız sürümde açık; değilse ödüllü reklamla
/// gün sonuna kadar açılır. Yalnızca kullanıcı isterse reklam izlenir.
class ExtraGate extends StatefulWidget {
  final ToolContext tool;
  final String feature;
  final Widget child;
  const ExtraGate({super.key, required this.tool, required this.feature, required this.child});

  @override
  State<ExtraGate> createState() => _ExtraGateState();
}

class _ExtraGateState extends State<ExtraGate> {
  bool? _open;

  @override
  void initState() {
    super.initState();
    widget.tool.unlockedToday(widget.feature).then((v) {
      if (mounted) setState(() => _open = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    if (_open == true) return widget.child;
    if (_open == null) return const SizedBox.shrink();
    return StudioPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const StudioIconBadge(Icons.lock_open_rounded, color: StudioLook.gem, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(L(t, 'extra_hint'), style: const TextStyle(color: Colors.white, height: 1.3))),
        ]),
        const SizedBox(height: 12),
        StudioButton(
          tone: StudioButtonTone.gold,
          icon: Icons.ondemand_video_rounded,
          label: L(t, 'unlock'),
          onPressed: () async {
            final ok = await t.unlockForToday(widget.feature);
            if (mounted) setState(() => _open = ok);
          },
        ),
      ]),
    );
  }
}

/// Bildirim izni: önce açıklama, sonra sistem isteği (bir kez).
Future<void> askNotifyOnce(BuildContext context, ToolContext t) async {
  if (!Notify.supported || await t.store.readBool('notifyAsked')) return;
  if (!context.mounted) return;
  final ok = await rationaleOnce(context, t, 'notify', Icons.notifications_active_rounded);
  if (ok) await Notify.requestPermission();
  await t.store.writeBool('notifyAsked', true);
}

/// Günlük tekrarlayan hatırlatmaları önümüzdeki [days] gün için kurar.
/// Kimlikler [base]..[base]+[slots]*[days] arasıdır; önce eskiler silinir.
Future<void> scheduleDaily({
  required int base,
  required List<int> minutes,
  required String title,
  required String body,
  int days = 3,
  int slots = 24,
}) async {
  if (!Notify.supported) return;
  for (var i = 0; i < slots * days; i++) {
    await Notify.cancel(base + i);
  }
  final now = DateTime.now();
  for (var d = 0; d < days; d++) {
    for (var k = 0; k < minutes.length && k < slots; k++) {
      final m = minutes[k];
      var when = DateTime(now.year, now.month, now.day, m ~/ 60, m % 60).add(Duration(days: d));
      if (!when.isAfter(now)) continue;
      await Notify.schedule(base + d * slots + k, title, body, when);
    }
  }
}

Future<void> cancelDaily(int base, {int days = 3, int slots = 24}) async {
  if (!Notify.supported) return;
  for (var i = 0; i < slots * days; i++) {
    await Notify.cancel(base + i);
  }
}

/// Uyarı kartı (sarı vurgu).
class WarnCard extends StatelessWidget {
  final String text;
  final IconData icon;
  const WarnCard(this.text, {super.key, this.icon = Icons.health_and_safety_rounded});

  @override
  Widget build(BuildContext context) => StudioPanel(
        borderColor: StudioLook.gold.withValues(alpha: 0.75),
        gradient: LinearGradient(colors: [StudioLook.gold.withValues(alpha: 0.16), StudioLook.gold.withValues(alpha: 0.06)]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: StudioLook.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, height: 1.35))),
        ]),
      );
}

/// Basit onay penceresi.
Future<bool> confirm(BuildContext context, ToolContext t, String text) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L(t, 'cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L(t, 'ok'))),
      ],
    ),
  );
  return r == true;
}

// --------------------------------------------------------------- çizim

/// Özgün çöp-adam çizimi; iki duruş arasında [t] (0..1) ile geçiş yapar.
class FigurePainter extends CustomPainter {
  final Pose a;
  final Pose? b;
  final double t;
  final Color color;

  /// Duvarın x konumu (0..100; duvar pilatesi), yoksa null.
  final double? wall;
  FigurePainter(this.a, this.b, this.t, this.color, {this.wall});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 100;
    final ox = (size.width - 100 * s) / 2, oy = (size.height - 100 * s) / 2;
    Offset p(int i) {
      final bb = b;
      final x = bb == null ? a[i * 2] : a[i * 2] + (bb[i * 2] - a[i * 2]) * t;
      final y = bb == null ? a[i * 2 + 1] : a[i * 2 + 1] + (bb[i * 2 + 1] - a[i * 2 + 1]) * t;
      return Offset(ox + x * s, oy + y * s);
    }

    final ground = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2 * s / 2;
    canvas.drawLine(Offset(ox + 4 * s, oy + 95 * s), Offset(ox + 96 * s, oy + 95 * s), ground);
    final w = wall;
    if (w != null) {
      // Duvar: hafif dolgu ve kenar çizgisi (figürün arkasında).
      final left = w < 50;
      final edge = ox + w * s;
      canvas.drawRect(
        Rect.fromLTRB(left ? ox : edge, oy + 2 * s, left ? edge : ox + 100 * s, oy + 95 * s),
        Paint()..color = Colors.white.withValues(alpha: 0.08),
      );
      canvas.drawLine(Offset(edge, oy + 2 * s), Offset(edge, oy + 95 * s), Paint()
        ..color = Colors.white54
        ..strokeWidth = 1.6 * s);
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 4.2 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void seg(int i, int j) => canvas.drawLine(p(i), p(j), line);
    // gövde, kollar (boyundan), bacaklar (kalçadan)
    seg(1, 2);
    seg(1, 3);
    seg(3, 4);
    seg(1, 5);
    seg(5, 6);
    seg(2, 7);
    seg(7, 8);
    seg(2, 9);
    seg(9, 10);
    canvas.drawCircle(p(0), 6.5 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(FigurePainter old) =>
      old.t != t || old.a != a || old.b != b || old.color != color || old.wall != wall;
}

/// Hareketli çizim: iki duruş arasında ritimle gidip gelir.
class Figure extends StatefulWidget {
  final Exercise ex;
  final double height;
  final bool moving;
  const Figure(this.ex, {super.key, this.height = 220, this.moving = true});

  @override
  State<Figure> createState() => _FigureState();
}

class _FigureState extends State<Figure> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.moving) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Figure old) {
    super.didUpdateWidget(old);
    if (widget.moving && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.moving && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: FigurePainter(widget.ex.a, widget.ex.b, Curves.easeInOut.transform(_c.value), s.accent, wall: widget.ex.wall),
        ),
      ),
    );
  }
}

/// Bir rutini (egzersiz + süre adımları, aralarda dinlenme) oynatır.
/// Ekran açık tutulur; çalışırken reklam gösterilmez (reklam yalnızca
/// araçtan çıkarken, merkezde).
class RoutinePlayer extends StatefulWidget {
  final ToolContext tool;
  final Routine routine;
  /// true: rutin bitti; false: kullanıcı durdurdu.
  final ValueChanged<bool> onDone;
  const RoutinePlayer({super.key, required this.tool, required this.routine, required this.onDone});

  @override
  State<RoutinePlayer> createState() => _RoutinePlayerState();
}

class _RoutinePlayerState extends State<RoutinePlayer> {
  late final List<Phase> _phases = [
    const Phase(0, 5, 0),
    for (var i = 0; i < widget.routine.steps.length; i++) ...[
      Phase(1, widget.routine.steps[i].$2, i, widget.routine.steps[i].$1),
      if (i < widget.routine.steps.length - 1 && widget.routine.rest > 0) Phase(2, widget.routine.rest, i),
    ],
  ];
  final TonePlayer _beep = TonePlayer();
  Timer? _tick;
  int _elapsedMs = 0;
  int _lastMs = 0;
  bool _running = true;
  int _lastIndex = -1;

  ToolContext get t => widget.tool;

  @override
  void initState() {
    super.initState();
    _lastMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
  }

  void _onTick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_running) _elapsedMs += now - _lastMs;
    _lastMs = now;
    final at = phaseAt(_phases, _elapsedMs ~/ 1000);
    if (at == null) {
      _tick?.cancel();
      unawaited(_beep.play(beepLong));
      widget.onDone(true);
      return;
    }
    if (at.index != _lastIndex) {
      if (_lastIndex >= 0) unawaited(_beep.play(beepShort));
      _lastIndex = at.index;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _beep.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = phaseAt(_phases, _elapsedMs ~/ 1000);
    if (at == null) return const SizedBox.shrink();
    final ph = _phases[at.index];
    final label = ph.label;
    String? next;
    for (var i = at.index + 1; i < _phases.length; i++) {
      final l = _phases[i].label;
      if (l != null) {
        next = l;
        break;
      }
    }
    final title = switch (ph.kind) { 0 => L(t, 'get_ready'), 2 => L(t, 'rest'), _ => L(t, 'ex_$label') };
    final shown = label ?? next;
    return Column(children: [
      AppPanel(
        child: Column(children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          if (shown != null) Figure(exercise(shown), moving: ph.kind == 1 && _running, height: 200),
          Text('${at.left}', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
          LinearProgressIndicator(value: 1 - at.left / math.max<int>(1, ph.seconds)),
          const SizedBox(height: 8),
          if (ph.kind == 1) Text(Lf(t, 'step_x', {'n': ph.round + 1, 'm': widget.routine.steps.length})),
          if (ph.kind != 1 && next != null) Text('${L(t, 'next_up')}: ${L(t, 'ex_$next')}'),
          if (label != null && kSaglikL.containsKey('tip_$label'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(L(t, 'tip_$label'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ),
        ]),
      ),
      Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
        AppButton(
          label: L(t, _running ? 'pause' : 'resume'),
          icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: () => setState(() => _running = !_running),
        ),
        AppButton(
          label: L(t, 'skip'),
          icon: Icons.skip_next_rounded,
          onPressed: () {
            var s = 0;
            for (var i = 0; i <= at.index; i++) {
              s += _phases[i].seconds;
            }
            setState(() => _elapsedMs = s * 1000);
          },
        ),
        AppButton(label: L(t, 'stop'), icon: Icons.stop_rounded, onPressed: () {
          _tick?.cancel();
          widget.onDone(false);
        }),
      ]),
    ]);
  }
}

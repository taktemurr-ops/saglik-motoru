/// Mobil/masaüstü: kesitler uygulamanın belgeler klasöründeki
/// `sleep_sounds/` altında durur; başka uygulamalarla paylaşılmaz,
/// hiçbir yere gönderilmez.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class ClipStore {
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<File?> _file(String name) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) return null;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/sleep_sounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  static Future<bool> save(String name, Uint8List bytes) async {
    try {
      final f = await _file(name);
      if (f == null) return false;
      await f.writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> read(String name) async {
    try {
      final f = await _file(name);
      if (f == null || !await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String name) async {
    try {
      final f = await _file(name);
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Kayıtlarda adı geçmeyen kesitleri siler (ör. "Tüm verilerimi sil"den sonra).
  static Future<void> prune(Set<String> keep) async {
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/sleep_sounds');
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        final n = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        if (e is File && n.endsWith('.wav') && !keep.contains(n)) await e.delete();
      }
    } catch (_) {}
  }
}

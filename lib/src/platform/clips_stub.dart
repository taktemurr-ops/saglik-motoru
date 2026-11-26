/// Web: gece kaydı yapılmaz, kesit saklanmaz.
library;

import 'dart:typed_data';

class ClipStore {
  static bool get supported => false;
  static Future<bool> save(String name, Uint8List bytes) async => false;
  static Future<Uint8List?> read(String name) async => null;
  static Future<void> delete(String name) async {}
  static Future<void> prune(Set<String> keep) async {}
}

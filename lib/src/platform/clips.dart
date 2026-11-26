/// Uyku sesi kesitleri: mobilde uygulamanın kendi belgeler klasöründe WAV
/// dosyası, web'de desteklenmez (kayıt yapılmaz).
library;

export 'clips_stub.dart' if (dart.library.io) 'clips_io.dart';

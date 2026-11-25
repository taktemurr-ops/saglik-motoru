/// Sağlık ve Spor motoru: 30 aracın gerçek uygulamaları, 33 dilde metinleri
/// ve merkez görünümü. İnce depolar (uyg-* ve taşınan app-0xx) buradan tek
/// bir araç alır. Hiçbir araç tıbbi cihaz değildir; teşhis, tedavi ya da doz
/// önermez.
library;

export 'src/data.dart' show Food, kFoods, foodByKey, Exercise, kExercises, Routine, kWorkouts, kStretches, kYoga;
export 'src/logic.dart';
export 'src/registry.dart';

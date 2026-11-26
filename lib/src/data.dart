/// Gömülü içerik: besin tablosu, özgün çöp-adam duruşları, egzersizler ve
/// rutinler. Çizimler bu dosyadaki koordinatlardan üretilir (fotoğraf ya da
/// üçüncü taraf görsel yok).
library;

// ------------------------------------------------------------ besinler

/// 100 g başına: enerji (kcal), protein, karbonhidrat, yağ (g).
/// [usda]: değer USDA FoodData Central (kamu malı) genel kayıtlarına göre
/// yuvarlatılmıştır; false ise geleneksel tarif için özgün yaklaşık tahmindir.
class Food {
  final String key;
  final double kcal, protein, carbs, fat;
  final bool usda;
  const Food(this.key, this.kcal, this.protein, this.carbs, this.fat, {this.usda = true});

  /// [grams] gram için değerler.
  ({double kcal, double protein, double carbs, double fat}) per(double grams) => (
        kcal: kcal * grams / 100,
        protein: protein * grams / 100,
        carbs: carbs * grams / 100,
        fat: fat * grams / 100,
      );
}

const List<Food> kFoods = [
  Food('apple', 52, 0.3, 14, 0.2),
  Food('banana', 89, 1.1, 23, 0.3),
  Food('orange', 47, 0.9, 12, 0.1),
  Food('strawberry', 32, 0.7, 7.7, 0.3),
  Food('grapes', 69, 0.7, 18, 0.2),
  Food('tomato', 18, 0.9, 3.9, 0.2),
  Food('cucumber', 15, 0.7, 3.6, 0.1),
  Food('carrot', 41, 0.9, 10, 0.2),
  Food('broccoli', 34, 2.8, 7, 0.4),
  Food('spinach', 23, 2.9, 3.6, 0.4),
  Food('potato', 87, 1.9, 20, 0.1),
  Food('rice', 130, 2.7, 28, 0.3),
  Food('pasta', 158, 5.8, 31, 0.9),
  Food('bread', 265, 9, 49, 3.2),
  Food('wholebread', 252, 12, 43, 3.5),
  Food('oats', 389, 17, 66, 7),
  Food('bulgur', 83, 3.1, 19, 0.2),
  Food('lentils', 116, 9, 20, 0.4),
  Food('chickpeas', 164, 8.9, 27, 2.6),
  Food('beans', 127, 8.7, 23, 0.5),
  Food('egg', 155, 13, 1.1, 11),
  Food('chicken', 165, 31, 0, 3.6),
  Food('beef', 250, 26, 0, 15),
  Food('salmon', 206, 22, 0, 12),
  Food('tuna', 116, 26, 0, 0.8),
  Food('milk', 61, 3.2, 4.8, 3.3),
  Food('yogurt', 61, 3.5, 4.7, 3.3),
  Food('whitecheese', 264, 14, 4, 21),
  Food('cheddar', 403, 25, 1.3, 33),
  Food('oliveoil', 884, 0, 0, 100),
  Food('butter', 717, 0.9, 0.1, 81),
  Food('almonds', 579, 21, 22, 50),
  Food('walnuts', 654, 15, 14, 65),
  Food('hazelnuts', 628, 15, 17, 61),
  Food('olives', 115, 0.8, 6, 11),
  Food('honey', 304, 0.3, 82, 0),
  Food('sugar', 387, 0, 100, 0),
  Food('avocado', 160, 2, 8.5, 15),
  Food('darkchoc', 598, 7.8, 46, 43),
  Food('lentilsoup', 60, 3.5, 8, 1.5, usda: false),
  Food('simit', 290, 9, 53, 5, usda: false),
  Food('menemen', 95, 5, 4, 7, usda: false),
  Food('ayran', 36, 1.7, 2.5, 2, usda: false),
  Food('beanstew', 110, 6, 14, 3.5, usda: false),
  Food('pilaf', 160, 2.8, 28, 4.5, usda: false),
  Food('ricepudding', 120, 3.5, 20, 3, usda: false),
  Food('sarma', 160, 2.5, 22, 7, usda: false),
  Food('lahmacun', 220, 9, 30, 7, usda: false),
];

Food? foodByKey(String key) {
  for (final f in kFoods) {
    if (f.key == key) return f;
  }
  return null;
}

// ------------------------------------------------------------- duruşlar

/// Çöp adam: baş, boyun, kalça, sol dirsek, sol el, sağ dirsek, sağ el,
/// sol diz, sol ayak, sağ diz, sağ ayak — 0..100 kutuda (x, y) çiftleri.
typedef Pose = List<double>;

const Pose pStand = [50, 12, 50, 22, 50, 52, 44, 36, 42, 50, 56, 36, 58, 50, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pJackOpen = [50, 12, 50, 22, 50, 52, 38, 14, 30, 4, 62, 14, 70, 4, 42, 72, 35, 93, 58, 72, 65, 93];
const Pose pSquat = [58, 32, 55, 42, 38, 66, 64, 46, 77, 46, 65, 48, 78, 48, 58, 68, 52, 93, 60, 70, 54, 93];
const Pose pPushUp = [80, 56, 72, 60, 40, 72, 72, 72, 72, 85, 73, 72, 73, 85, 24, 79, 8, 85, 24, 79, 8, 85];
const Pose pPushDown = [80, 74, 72, 78, 40, 81, 62, 72, 72, 85, 63, 72, 73, 85, 24, 83, 8, 85, 24, 83, 8, 85];
const Pose pPlank = [80, 66, 72, 70, 40, 76, 72, 85, 84, 85, 73, 85, 85, 85, 24, 80, 8, 85, 24, 80, 8, 85];
const Pose pLunge = [50, 14, 50, 24, 50, 54, 43, 40, 47, 53, 57, 40, 53, 53, 64, 68, 66, 93, 40, 86, 27, 92];
const Pose pBridgeUp = [14, 82, 22, 82, 50, 64, 32, 84, 44, 85, 33, 84, 45, 85, 66, 58, 70, 85, 66, 58, 70, 85];
const Pose pBridgeDown = [14, 82, 22, 82, 48, 82, 32, 84, 44, 85, 33, 84, 45, 85, 64, 64, 70, 85, 64, 64, 70, 85];
const Pose pHighKneeL = [50, 12, 50, 22, 50, 52, 58, 32, 62, 22, 42, 40, 40, 52, 58, 52, 56, 72, 53, 72, 54, 93];
const Pose pHighKneeR = [50, 12, 50, 22, 50, 52, 42, 32, 38, 22, 58, 40, 60, 52, 47, 72, 46, 93, 42, 52, 44, 72];
const Pose pClimbA = [78, 56, 70, 60, 42, 70, 71, 72, 72, 85, 72, 72, 73, 85, 56, 74, 48, 82, 26, 78, 10, 85];
const Pose pClimbB = [78, 56, 70, 60, 42, 70, 71, 72, 72, 85, 72, 72, 73, 85, 26, 78, 10, 85, 56, 74, 48, 82];
const Pose pWallSit = [30, 30, 30, 40, 30, 64, 40, 52, 50, 62, 41, 52, 51, 62, 54, 64, 54, 93, 55, 64, 55, 93];
const Pose pCrunchUp = [30, 62, 34, 70, 50, 84, 28, 62, 26, 54, 29, 63, 27, 55, 64, 66, 74, 85, 64, 66, 74, 85];
const Pose pCrunchDown = [14, 82, 22, 83, 50, 84, 16, 76, 12, 74, 17, 77, 13, 75, 64, 66, 74, 85, 64, 66, 74, 85];
const Pose pNeckTilt = [44, 14, 50, 22, 50, 52, 44, 36, 42, 50, 56, 36, 58, 50, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pNeckTilt2 = [56, 14, 50, 22, 50, 52, 44, 36, 42, 50, 56, 36, 58, 50, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pShoulderUp = [50, 12, 50, 20, 50, 52, 40, 30, 38, 42, 60, 30, 62, 42, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pChestOpen = [50, 12, 50, 22, 50, 52, 36, 30, 26, 36, 64, 30, 74, 36, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pSideBendL = [38, 16, 43, 25, 50, 52, 36, 40, 34, 52, 52, 12, 36, 6, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pSideBendR = [62, 16, 57, 25, 50, 52, 48, 12, 64, 6, 64, 40, 66, 52, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pFold = [64, 78, 60, 68, 48, 50, 60, 80, 58, 92, 61, 80, 59, 92, 49, 72, 48, 93, 51, 72, 50, 93];
const Pose pQuad = [50, 12, 50, 22, 50, 52, 58, 34, 62, 46, 44, 44, 40, 62, 48, 72, 48, 93, 52, 74, 40, 62];
const Pose pCalf = [62, 18, 59, 28, 48, 54, 70, 30, 82, 28, 71, 31, 83, 29, 60, 72, 64, 93, 38, 74, 30, 93];
const Pose pHipFlex = [50, 26, 50, 36, 50, 64, 44, 48, 48, 62, 56, 48, 52, 62, 64, 72, 66, 93, 40, 93, 24, 93];
const Pose pTree = [50, 12, 50, 22, 50, 52, 42, 10, 50, 2, 58, 10, 50, 2, 49, 72, 49, 93, 64, 64, 51, 70];
const Pose pWarrior = [52, 16, 50, 26, 50, 56, 36, 28, 22, 28, 64, 28, 78, 28, 36, 75, 22, 93, 70, 70, 72, 93];
const Pose pTriangle = [72, 38, 64, 40, 50, 58, 60, 24, 56, 8, 70, 60, 74, 80, 38, 76, 28, 93, 62, 76, 72, 93];
const Pose pDownDog = [74, 78, 70, 70, 50, 40, 74, 80, 78, 90, 75, 80, 79, 90, 36, 66, 22, 93, 37, 66, 23, 93];
const Pose pChild = [64, 84, 56, 80, 30, 80, 72, 86, 86, 90, 73, 86, 87, 90, 40, 90, 24, 92, 41, 90, 25, 92];
const Pose pCow = [80, 54, 70, 66, 36, 64, 70, 78, 70, 92, 71, 78, 71, 92, 36, 92, 20, 92, 37, 92, 21, 92];
const Pose pCat = [76, 76, 70, 68, 36, 62, 70, 78, 70, 92, 71, 78, 71, 92, 36, 92, 20, 92, 37, 92, 21, 92];
const Pose pCobra = [72, 56, 66, 66, 40, 88, 64, 80, 66, 90, 65, 80, 67, 90, 26, 90, 10, 90, 26, 90, 10, 90];
const Pose pRest = [12, 86, 20, 86, 50, 86, 32, 88, 44, 89, 33, 88, 45, 89, 68, 87, 86, 88, 68, 87, 86, 88];

/// Egzersiz: iki duruş arasında gidip gelir; [b] yoksa duruş tutulur.
/// [wall]: duvar pilatesi hareketlerinde duvarın x konumu (0..100), çizimde
/// dikey bir çizgi olarak görünür.
class Exercise {
  final String key;
  final Pose a;
  final Pose? b;
  final double? wall;
  const Exercise(this.key, this.a, [this.b, this.wall]);
}

// ------------------------------------------------------- duvar pilatesi
// Yandan görünüş; duvar dikey çizgi. Koordinatlar özgündür (fotoğraf yok).

const Pose pwSit = [30, 30, 30, 40, 30, 64, 38, 52, 47, 60, 39, 52, 48, 61, 52, 64, 52, 93, 53, 64, 53, 93];
const Pose pwAngelDown = [50, 12, 50, 22, 50, 52, 36, 22, 34, 10, 64, 22, 66, 10, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pwAngelUp = [50, 12, 50, 22, 50, 52, 42, 10, 46, 2, 58, 10, 54, 2, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pwPushOut = [60, 16, 58, 26, 46, 54, 68, 30, 77, 30, 68, 31, 77, 31, 41, 74, 36, 93, 42, 74, 37, 93];
const Pose pwPushIn = [67, 17, 64, 27, 50, 55, 64, 40, 77, 30, 64, 41, 77, 31, 43, 74, 36, 93, 44, 74, 37, 93];
const Pose pwPlank = [66, 22, 62, 30, 44, 58, 77, 36, 77, 24, 77, 37, 77, 25, 37, 76, 30, 93, 38, 76, 31, 93];
const Pose pwCalfDown = [60, 12, 60, 22, 58, 52, 68, 30, 77, 28, 68, 31, 77, 29, 58, 72, 58, 93, 59, 72, 59, 93];
const Pose pwCalfUp = [60, 7, 60, 17, 58, 47, 68, 26, 77, 24, 68, 27, 77, 25, 58, 68, 60, 89, 59, 68, 61, 89];
const Pose pwKickBack = [63, 14, 62, 24, 56, 52, 69, 31, 77, 28, 69, 32, 77, 29, 56, 72, 56, 93, 46, 66, 32, 74];
const Pose pwSideA = [50, 12, 50, 22, 50, 52, 38, 34, 27, 40, 60, 40, 54, 50, 47, 72, 46, 93, 53, 72, 54, 93];
const Pose pwSideB = [48, 12, 49, 22, 50, 52, 38, 34, 27, 40, 60, 40, 54, 50, 47, 72, 46, 93, 62, 70, 72, 82];
const Pose pwBridgeDown = [14, 86, 22, 86, 50, 86, 32, 88, 44, 89, 33, 88, 45, 89, 66, 66, 81, 72, 67, 66, 81, 73];
const Pose pwBridgeUp = [14, 86, 22, 86, 52, 68, 32, 88, 44, 89, 33, 88, 45, 89, 68, 58, 81, 70, 69, 58, 81, 71];
const Pose pwLegsUp = [14, 88, 22, 88, 54, 88, 30, 90, 40, 91, 31, 90, 41, 91, 57, 64, 58, 40, 58, 64, 59, 40];
const Pose pwRollUp = [44, 12, 44, 22, 44, 52, 46, 36, 47, 50, 46, 37, 47, 51, 46, 72, 50, 93, 47, 72, 51, 93];
const Pose pwRollDown = [54, 58, 52, 48, 43, 50, 56, 64, 58, 76, 57, 64, 59, 76, 47, 72, 50, 93, 48, 72, 51, 93];

const List<Exercise> kExercises = [
  Exercise('jumping_jacks', pStand, pJackOpen),
  Exercise('squat', pStand, pSquat),
  Exercise('pushup', pPushUp, pPushDown),
  Exercise('lunge', pStand, pLunge),
  Exercise('plank', pPlank),
  Exercise('glute_bridge', pBridgeDown, pBridgeUp),
  Exercise('high_knees', pHighKneeL, pHighKneeR),
  Exercise('climber', pClimbA, pClimbB),
  Exercise('wall_sit', pWallSit),
  Exercise('crunch', pCrunchDown, pCrunchUp),
  Exercise('neck_tilt', pNeckTilt, pNeckTilt2),
  Exercise('shoulder_roll', pStand, pShoulderUp),
  Exercise('chest_open', pChestOpen),
  Exercise('side_bend', pSideBendL, pSideBendR),
  Exercise('forward_fold', pFold),
  Exercise('quad_stretch', pQuad),
  Exercise('calf_stretch', pCalf),
  Exercise('hip_flexor', pHipFlex),
  Exercise('y_mountain', pStand),
  Exercise('y_tree', pTree),
  Exercise('y_warrior', pWarrior),
  Exercise('y_triangle', pTriangle),
  Exercise('y_down_dog', pDownDog),
  Exercise('y_child', pChild),
  Exercise('y_cat_cow', pCow, pCat),
  Exercise('y_cobra', pCobra),
  Exercise('y_bridge', pBridgeUp),
  Exercise('y_rest', pRest),
  // duvar pilatesi
  Exercise('wp_wall_sit', pwSit, null, 24),
  Exercise('wp_wall_angels', pwAngelDown, pwAngelUp),
  Exercise('wp_wall_pushup', pwPushOut, pwPushIn, 79),
  Exercise('wp_wall_plank', pwPlank, null, 79),
  Exercise('wp_calf_raise', pwCalfDown, pwCalfUp, 79),
  Exercise('wp_glute_kick', pwCalfDown, pwKickBack, 79),
  Exercise('wp_side_leg', pwSideA, pwSideB, 25),
  Exercise('wp_wall_bridge', pwBridgeDown, pwBridgeUp, 83),
  Exercise('wp_legs_up', pwLegsUp, null, 61),
  Exercise('wp_roll_down', pwRollUp, pwRollDown, 40),
];

Exercise exercise(String key) => kExercises.firstWhere((e) => e.key == key);

/// Rutin: (egzersiz, saniye) adımları ve adımlar arası dinlenme.
class Routine {
  final String key;
  final List<(String, int)> steps;
  final int rest;

  /// Ödüllü reklamla (ya da Premium ile) bugün açılan ekstra rutin mi?
  final bool extra;
  const Routine(this.key, this.steps, {this.rest = 0, this.extra = false});
  int get seconds => steps.fold(0, (a, s) => a + s.$2) + rest * (steps.length - 1);
}

const List<Routine> kWorkouts = [
  Routine('r_full', [('jumping_jacks', 30), ('squat', 30), ('pushup', 30), ('glute_bridge', 30), ('plank', 30), ('crunch', 30)], rest: 15),
  Routine('r_cardio', [('jumping_jacks', 40), ('high_knees', 30), ('climber', 30), ('squat', 40), ('lunge', 40), ('high_knees', 30)], rest: 15),
  Routine('r_core', [('plank', 30), ('crunch', 40), ('climber', 30), ('glute_bridge', 40), ('wall_sit', 30)], rest: 15),
  Routine('r_legs', [('squat', 45), ('lunge', 45), ('wall_sit', 40), ('glute_bridge', 45), ('high_knees', 30), ('squat', 45)], rest: 20, extra: true),
];

const List<Routine> kStretches = [
  Routine('r_morning', [('neck_tilt', 30), ('shoulder_roll', 30), ('side_bend', 30), ('forward_fold', 30), ('quad_stretch', 30), ('calf_stretch', 30)]),
  Routine('r_desk', [('neck_tilt', 30), ('shoulder_roll', 30), ('chest_open', 30), ('side_bend', 30), ('hip_flexor', 30)]),
  Routine('r_evening', [('forward_fold', 40), ('hip_flexor', 40), ('quad_stretch', 40), ('calf_stretch', 40), ('y_child', 60)], extra: true),
];

const List<Routine> kYoga = [
  Routine('r_gentle', [('y_mountain', 30), ('y_cat_cow', 45), ('y_down_dog', 40), ('y_child', 45), ('y_cobra', 30), ('y_rest', 60)]),
  Routine('r_balance', [('y_mountain', 30), ('y_tree', 40), ('y_warrior', 40), ('y_triangle', 40), ('y_tree', 40), ('y_rest', 60)]),
  Routine('r_calm', [('y_child', 60), ('y_cat_cow', 45), ('y_bridge', 40), ('y_cobra', 30), ('y_rest', 90)], extra: true),
];

/// Duvar pilatesi rutinleri (adımlar arası kısa dinlenme).
const List<Routine> kWallPilates = [
  Routine('r_wp_start', [('wp_wall_angels', 40), ('wp_calf_raise', 40), ('wp_wall_pushup', 40), ('wp_wall_sit', 30), ('wp_wall_bridge', 40), ('wp_legs_up', 60)], rest: 15),
  Routine('r_wp_core', [('wp_roll_down', 40), ('wp_wall_plank', 30), ('wp_wall_bridge', 45), ('wp_wall_sit', 40), ('wp_wall_plank', 30), ('wp_legs_up', 60)], rest: 15),
  Routine('r_wp_lower', [('wp_calf_raise', 45), ('wp_glute_kick', 45), ('wp_side_leg', 45), ('wp_wall_sit', 45), ('wp_wall_bridge', 45), ('wp_legs_up', 60)], rest: 15),
  Routine('r_wp_upper', [('wp_wall_angels', 45), ('wp_wall_pushup', 45), ('wp_wall_plank', 40), ('wp_roll_down', 45), ('wp_wall_pushup', 45), ('wp_legs_up', 60)], rest: 15),
  Routine('r_wp_relax', [('wp_roll_down', 45), ('wp_wall_angels', 45), ('wp_legs_up', 120)], extra: true),
];

/// 28 günlük duvar pilatesi planı: her hafta 5 egzersiz günü, 2 dinlenme
/// günü (null). Haftalar ilerledikçe süre [wallPilatesScale] ile uzar.
const List<String?> kWallPilatesPlan = [
  'r_wp_start', 'r_wp_lower', null, 'r_wp_upper', 'r_wp_core', 'r_wp_start', null,
  'r_wp_lower', 'r_wp_upper', null, 'r_wp_core', 'r_wp_start', 'r_wp_lower', null,
  'r_wp_upper', 'r_wp_core', null, 'r_wp_lower', 'r_wp_upper', 'r_wp_core', null,
  'r_wp_start', 'r_wp_lower', null, 'r_wp_upper', 'r_wp_core', 'r_wp_lower', null,
];

/// Plan haftasına göre hareket süresi çarpanı (1. hafta 1.0 → 4. hafta 1.3).
double wallPilatesScale(int day) => 1.0 + 0.1 * (day.clamp(0, 27) ~/ 7);

/// Planın [day]. günü (0'dan) için ölçeklenmiş rutin; dinlenme günüyse null.
Routine? wallPilatesDay(int day) {
  final key = kWallPilatesPlan[day.clamp(0, kWallPilatesPlan.length - 1)];
  if (key == null) return null;
  final base = kWallPilates.firstWhere((r) => r.key == key);
  final k = wallPilatesScale(day);
  return Routine(base.key, [for (final s in base.steps) (s.$1, (s.$2 * k / 5).round() * 5)], rest: base.rest);
}

/// Göz egzersizleri: çizim yerine hareketli nokta kılavuzu.
const List<(String, int)> kEyeSteps = [
  ('eye_lr', 20), ('eye_ud', 20), ('eye_circle', 20), ('eye_focus', 20), ('eye_blink', 15), ('eye_far', 20),
];

/// Ağırlık antrenmanı için hazır hareket adları (kullanıcı kendi adını da ekler).
const List<String> kLifts = [
  'w_squat', 'w_bench', 'w_deadlift', 'w_ohp', 'w_row', 'w_pullup', 'w_curl', 'w_triceps', 'w_legpress', 'w_lunge',
];

/// Nefes kalıpları: (ad, nefes al, tut, ver, tut) saniye.
const List<(String, int, int, int, int)> kBreaths = [
  ('b_calm', 4, 0, 6, 0),
  ('b_box', 4, 4, 4, 4),
  ('b_even', 5, 0, 5, 0),
  ('b_relax', 4, 7, 8, 0),
];

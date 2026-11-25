# saglik-motoru

Sağlık ve Spor ailesinin motoru: 30 aracın gerçek uygulamaları, 33 dilde metinleri ve merkez
görünümü (onaylı oyun merkezi tasarımının deniz yeşili zemin, mercan vurgulu tonu).

- Çatı: `studio_core/apps` (AppTool, AppHubShell, reklam/satın alma, gizlilik, favoriler).
- Her araç kendi ince deposunda yayımlanır (`uyg-*`; taşınan 7 araç kendi `app-0xx` deposunda);
  merkez uygulama `merkez-saglik-ve-spor`.
- **Tıbbi cihaz değildir.** Bütün araçlar `AppDisclaimer.wellness` bandını gösterir; teşhis, tedavi,
  ölçüm doğruluğu ya da doz önerisi yoktur. Tansiyon/şeker günlüğü değerleri yorumlamaz, yalnızca
  kullanıcının (doktorunun verdiği) aralığıyla karşılaştırır. İlaç hatırlatıcı yalnızca kullanıcının
  girdiği saatlerde hatırlatır.
- **Yeme bozukluğu koruması** (`lib/src/logic.dart`): kalori hedefi 1200/1500 kcal altına inmez
  (`calorieFloor`), hedef kilo VKİ 18,5 altına ayarlanamaz (`safeTargetWeight`), oruç planı en çok
  20 saattir (`kMaxFastHours`); hızlı kilo kaybında nazik uyarı; beslenme araçlarında destek bilgisi.
- **Ruh hali günlüğü**: kriz sözcüklerinde (33 dilde, `kCrisisWords`) ve "çok kötü" seçiminde ülkeye
  göre acil numara, bilinen ücretsiz destek hattı (`kHelplines`) ve findahelpline.com gösterilir.
- **Diş fırçalama (çocuk)**: reklam/ödüllü reklam/satın alma yok; araç açıkken ve çıkarken
  `services.lastInterstitialMs` güncellenerek merkezin geçiş reklamı susturulur (Families).
- Çevrimdışı. Besin tablosu gömülü: USDA FoodData Central (kamu malı) genel kayıtları + geleneksel
  yemekler için özgün tahminler (`lib/src/data.dart`). Open Food Facts barkod araması bu sürümde yok.
- Egzersiz, esneme ve yoga çizimleri koddaki koordinatlardan çizilen özgün çöp-adam figürleridir
  (fotoğraf/video/üçüncü taraf görsel yok). Görme testi özgün nokta levhaları ve halka kullanır
  (Ishihara kopyası yok); işitme testi göreli puan verir (dB HL iddiası yok).
- Adım sayar `pedometer` (Android ACTIVITY_RECOGNITION, iOS hareket); koşu/bisiklet yalnızca ekran
  açıkken GPS (arka plan konumu ve ön plan hizmeti yok); nabız tahmini kamera + flaş (PPG).
  Sensörü olmayan cihazlarda ve web'de araç "bu cihazda yok" der, çökmez.
- Ödüllü ekstralar: ek egzersiz/esneme/yoga rutinleri ve tansiyon/şeker CSV kopyalama
  (Premium/Reklamsız sürümde her zaman açık).

Metinler `proto/apps/saglik/` altındaki dosyalardan `mkengine.py` ile üretilir
(`lib/src/tx.dart`, `lib/src/registry.dart`); ince depolar ve merkez `mkrepos.py` ile.

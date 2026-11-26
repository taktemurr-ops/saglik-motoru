# saglik-motoru

Sağlık ve Spor ailesinin motoru: 35 aracın gerçek uygulamaları, 33 dilde metinleri ve merkez
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

## 2. tur ekleri
- **30 Gün Meydan Okuma**: 8 hareket (çömelme, şınav, plank, hamle, mekik, duvarda oturma, köprü,
  zıplama), üç seviye, her 4. gün dinlenme, günde bir adım; kaçırılan gün planı bozmaz.
- **Kafein Takibi**: yaklaşık değerli hazır içecekler ve kendi içeceğin, kendi belirlediğin sınır,
  7 günlük grafik, yarılanma ömrüyle kaba "kalan kafein" tahmini (tıbbi değil).
- **Yürüyüş Rotaları**: yalnızca ekran açıkken GPS kaydı, tırmanış/iniş, tahmini adım, adlı rotalar,
  yükseklik profili, GPX paylaşma (`share_plus`), kayıtlı rotayı yeniden yürürken rotaya uzaklık ve
  kalan mesafe. Harita karosu yok; tamamen çevrimdışı.

## 4. tur araçları
- **Duvar Pilatesi** (`tools/pilates.dart`, `data.dart`): kodla çizilmiş duvar + çöp adam (10 özgün hareket),
  5 rutin (biri ödüllü reklamla/Premium ile), 28 günlük plan (haftada 5 seans, 2 dinlenme; süre her hafta %10
  uzar), hareket ipuçları oynatıcıda görünür. Esenlik uyarısı; tıbbi iddia yok.
- **Uyku Sesi Kaydı** (`tools/sleep_sound.dart`, `sleep_sound.dart`, `platform/clips*.dart`): gece boyunca
  mikrofon düzeyi (16 kHz PCM, `record`) yarım saniyelik pencerelerle ortam düzeyine göre izlenir; belirgin ses
  olayları zamanıyla, isteğe bağlı ≤20 sn kesitler (gecede ≤40, WAV) yalnızca uygulamanın belgeler klasöründe
  saklanır. Dakika başına düzey grafiği, saat başına olay, etken notları. Ses türü sınıflandırılmaz; horlama/apne
  **tespiti ya da teşhisi yoktur**. Kayıt sırasında ekran açık tutulur (wakelock); ön plan hizmeti yoktur, ekran
  kilitlenirse kayıt durabilir (kullanıcıya söylenir). Web'de desteklenmez (dürüst bilgi kartı).


# MC-AWARE (Majority Class Aware) Projesi

TÜBİTAK 2209-A Lisans Araştırma Projesi
**Yürütücü:** Mehmet Ali KURT
**Yardımcı:** Şevval DEMİR  
**Danışman:** Övgücan KARADAĞ ERDEMİR
**Tarih:** Mayıs 2026 | **Durum:** 22 Deney Tamamlandı — v3 NİHAİ

## Proje Hakkında
Bu proje, BIST (Borsa İstanbul) günlük yön tahmininde derin öğrenme modellerinin "Majority Class" (MC) tuzağına düşmesini engelleyip, modellerin gerçek tahmin gücünü ölçmeyi hedefler. MC tuzağı çözüldüğünde, makro-hassas BIST varlıklarında derin öğrenme modellerinin eğitim/test korelasyon kırılmaları (concept drift) nedeniyle dönemsel ve varlık-özgü ters-yön örüntüsü sergilediği tespit edilmiştir.

## 🔓 Şeffaflık ve Açık Bilim Beyanı (Reproducibility)
TÜBİTAK 2209-A lisans projesi kapsamında koşturulan **350'den fazla konfigürasyonun** tamamı şeffaftır. Bu repoda yer alan tüm deneyler, kodlar ve görsel çıktılar akademik hakem denetimine %100 açık olacak şekilde versiyon kontrolüne (Git) alınmıştır. Veri seti 2014-2023 yıllarını kapsamakta olup, test seti dışarıda bırakılarak (OOT) Walk-Forward Cross Validation ile model performansı dürüstçe belgelenmiştir.

## 🚀 İnteraktif Dashboard (Tek Dosya Mucizesi)
Tüm sonuçları, bulguları ve görsel analizleri incelemek için herhangi bir kurulum yapmanıza gerek yoktur:
- `Docs/Dashboard/index.html` dosyasına çift tıklamanız yeterlidir.
- Bu dosya CSS, JavaScript ve 17 adet yüksek çözünürlüklü grafiği **kendi içinde (Base64) barındıran** özel bir interaktif rapordur. İnternet bağlantısı olmasa bile tüm grafikler ve animasyonlar kusursuz çalışır.


## Proje Klasör Yapısı

```
00_Tubitak/
├── Docs/                  # Dokümantasyon ve Raporlar
│   ├── Dashboard/         # İnteraktif web dashboard (HTML/CSS/JS)
│   ├── OZET.txt           # Hoca Brief v3 NİHAİ (ana referans)
│   ├── TUBITAK_2209A_Nihai_Rapor.txt  # TÜBİTAK Nihai Rapor v3
│   ├── PROJE_DURUMU.txt   # Tüm deney süreçlerinin ana günlüğü (SSOT)
│   └── TUBITAK_2209A_Proje_Onerisi.pdf # Orijinal başvuru dosyası
├── Gorseller/             # 17 adet yüksek çözünürlüklü (300 DPI) grafik
├── Kodlar/                # Tüm deneylerin R kodları
│   ├── 01_prototypes/     # BiLSTM v1-v6, LSTM, multi-arch (12 dosya)
│   ├── 02_ablation/       # Feature, IN_LEN, korelasyon ablasyonları (4 dosya)
│   ├── 03_validation/     # Walk-forward, NASDAQ, multi-stock (4 dosya)
│   ├── 04_baseline/       # Klasik ML ve Ensemble yöntemleri (4 dosya)
│   ├── 05_diagnostic/     # MI ve teşhis testleri (2 dosya)
│   ├── 06_ek_deneyler/    # Sektörel karşıt-testler (3 dosya)
│   └── FINAL_RELEASE/     # Nihai yayın paketi (8 dosya)
├── Sonuclar/              # Kodların ürettiği tüm çıktılar
│   ├── predictions/       # Tahmin serileri (18 dosya)
│   ├── summaries/         # Değerlendirme tabloları (49 dosya)
│   ├── thresholds/        # Olasılık eşik ızgaraları (13 dosya)
│   └── diagnostics/       # İstatistiksel tanılar (24 dosya)
└── README.md              # Bu dosya
```

## Temel Bulgular (22 Deney)
- **MC Tuzağı Çözümü:** 90/90 konfigürasyonda MC=0 (class_weight=balanced + MC-Aware loss)
- **Anti-Prediktif Davranış:** THYAO'da 118/120 konfigürasyonda flip>naive (tek split, p≈3×10⁻¹⁴)
- **Walk-Forward:** 3/7 fold dönemsel — etki evrensel değil, rejim-bağımlı
- **IN_LEN Kırılganlık:** Anti-pred etki IN_LEN=2'ye özgü; IN_LEN={5,10}'da 0/15
- **Mimari-Bağımsızlık:** 6 DL mimarisi + Ensemble + Attention → hepsi aynı yönde
- **Klasik ML Negatif Kontrol:** THYAO/GARAN/AAPL'da 0/8 beats_naive (EMH tutarlı)
- **Sektörel Kontrast:** Sigorta 2/5 vs Holding 0/5 sıkı anti-pred (ön kanıt)
- **Mekanizma:** Makro değişkenlerin korelasyon kırılması → gerekli ama yetersiz koşul

Tüm bulguların detaylı analizi: `Docs/TUBITAK_2209A_Nihai_Rapor.txt`

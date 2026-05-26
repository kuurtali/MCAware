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
├── Docs/                  # Dokümantasyon — Dashboard klasörü + 6 belge dosyası
│   ├── Dashboard/         # İnteraktif web dashboard (HTML/CSS/JS)
│   ├── OZET.txt           # Hoca Brief v4 NİHAİ (ana referans)
│   ├── PROJECT_REPORT.txt # Detaylı proje raporu (İngilizce)
│   ├── TUBITAK_2209A_Nihai_Rapor.txt  # TÜBİTAK Nihai Rapor v4
│   ├── PROJE_DURUMU.txt   # Tüm deney süreçlerinin ana günlüğü (SSOT)
│   ├── TUBITAK_2209A_Proje_Onerisi.pdf
│   └── MC_AWARE_Birlesitirilmis_Rapor.docx  # Birleştirilmiş resmi doküman
├── Gorseller/             # 33 adet yüksek çözünürlüklü (300 DPI) grafik
├── Kodlar/                # 7 alt dizin, ~40 R/Python scripti
│   ├── 01_prototypes/     # BiLSTM v1-v6, LSTM, multi-arch (12 dosya)
│   ├── 02_ablation/       # Feature, IN_LEN, korelasyon ablasyonları (4 dosya)
│   ├── 03_validation/     # Walk-forward, NASDAQ, multi-stock (4 dosya)
│   ├── 04_baseline/       # Klasik ML ve Ensemble yöntemleri (4 dosya)
│   ├── 05_diagnostic/     # MI ve teşhis testleri (2 dosya)
│   ├── 06_ek_deneyler/    # Sektörel karşıt-testler (3 dosya)
│   ├── 07_faz2_deneyler/  # Faz 2 analizleri ve görselleştirme scriptleri (Python)
│   └── FINAL_RELEASE/     # Nihai yayın paketi (7 R + 1 README = 8 dosya)
├── Sonuclar/              # 4 alt dizin (predictions, summaries, thresholds, diagnostics), ~115 CSV
│   ├── predictions/       # Tahmin serileri
│   ├── summaries/         # Değerlendirme tabloları
│   ├── thresholds/        # Olasılık eşik ızgaraları
│   └── diagnostics/       # İstatistiksel tanılar
└── README.md              # Bu dosya
```

## Temel Bulgular (22 Deney)
- **MC Tuzağı Çözümü:** 90/90 konfigürasyonda MC=0 (class_weight=balanced + MC-Aware loss)
- **Anti-Prediktif Davranış:** THYAO'da 118/120 konfigürasyonda flip>naive (tek split, p≈3×10⁻¹⁴)
- **Walk-Forward:** 3/7 fold dönemsel — etki evrensel değil, rejim-bağımlı
- **IN_LEN Kırılganlık:** Anti-pred etki IN_LEN=2'ye özgü; IN_LEN={5,10}'da 0/15
- **Mimari-Bağımsızlık:** 6 DL mimarisi + Ensemble + Attention → hepsi aynı yönde
- **Klasik ML Negatif Kontrol:** THYAO/GARAN/AAPL'da 1/11 beats_naive (yalnızca GARAN RF sınırda) (EMH tutarlı)
- **Sektörel Kontrast:** Sigorta 2/5 vs Holding 0/5 sıkı anti-pred (ön kanıt)
- **Mekanizma:** Makro değişkenlerin korelasyon kırılması → gerekli ama yetersiz koşul

Tüm bulguların detaylı analizi: `Docs/TUBITAK_2209A_Nihai_Rapor.txt`

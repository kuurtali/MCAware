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

## 🚀 İnteraktif Dashboard (Canlı Demo)
Artık projeyi bilgisayarınıza kurmanıza gerek kalmadan tüm arayüzü ve tahmin motorunu internet üzerinden canlı olarak test edebilirsiniz!
👉 **[TÜBİTAK MC-AWARE Canlı Demo İçin Tıklayın](https://tubitak-mcaware.streamlit.app/)**

*(Eski HTML tabanlı raporlar `Docs/Dashboard/index.html` içerisinde yedeklenmiştir).*

## 🛠 Nasıl Çalıştırılır (How to Run)

Bu projeyi yerel makinenizde çalıştırmak ve deneyleri yeniden üretmek (reproduce) için aşağıdaki adımları izleyin:

1. **Repoyu Klonlayın:**
   ```bash
   git clone https://github.com/kuurtali/Tubitak-2209A-MCAware.git
   cd Tubitak-2209A-MCAware
   ```

2. **Gerekli Paketleri Kurun:**
   Proje R dilinde yazılmış olup `keras3` (TensorFlow) bağımlılığına sahiptir. Gerekli tüm paketleri kurmak için R veya RStudio üzerinden şu betiği çalıştırın:
   ```R
   source("install_packages.R")
   ```

3. **Modelleri Eğitme ve Test Etme:**
   `Kodlar/FINAL_RELEASE` klasöründeki ana test scriptlerini sırasıyla çalıştırabilirsiniz. Örneğin, BIST-5 Sigorta sektörü testini başlatmak için:
   ```bash
   Rscript Kodlar/FINAL_RELEASE/01_Sektorel_Karsilastirma_Sigorta.R
   ```
   *Not: Eğitim süreleri donanımınıza (CPU/GPU) bağlı olarak 45-60 dakika sürebilir. Çıktılar otomatik olarak `Sonuclar/summaries` klasörüne kaydedilecektir.*

---

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

---

## 🇬🇧 English Summary

### About

This project investigates the **Majority Class (MC) trap** in deep learning models applied to daily stock direction prediction on BIST (Borsa Istanbul). Funded under **TÜBİTAK 2209-A** undergraduate research grant.

After solving the MC trap (where models predict only the majority class), we discovered that DL models exhibit **anti-predictive behavior** on macro-sensitive BIST assets — systematically predicting the *opposite* direction due to concept drift in macroeconomic variables between training and test periods.

### Key Findings (22 Experiments)

| Finding | Detail |
|---------|--------|
| **MC Trap Solved** | 90/90 configs achieve MC=0 (class_weight=balanced + MC-Aware loss) |
| **Anti-Predictive Behavior** | 118/120 configs on THYAO predict opposite direction (p ≈ 3×10⁻¹⁴) |
| **Architecture-Independent** | 6 DL architectures (BiLSTM, GRU, Conv1D, TCN, Transformer, RNN) + Ensemble + Attention — all show same pattern |
| **Walk-Forward CV** | 3/7 folds show anti-predictive effect — regime-dependent, not universal |
| **Mechanism** | Macro-variable correlation breakdown (USDTRY: train=0.91 → test=0.41) — necessary but insufficient condition |
| **Cross-Market** | NASDAQ shows normal behavior — effect is specific to emerging markets |
| **Classical ML Control** | 1/11 beats naive across THYAO/GARAN/AAPL — consistent with EMH |

### Interactive Dashboard

Open `Docs/Dashboard/index.html` — a self-contained HTML file with 17 high-resolution charts embedded as Base64. No installation or internet required.

### Methodology

- **Data:** BIST daily prices (2014–2023), macro variables (USDTRY, WTI Oil, TCMB policy rate)
- **Validation:** Walk-Forward Cross Validation (7 folds), Out-of-Time test set
- **Reproducibility:** Fixed seeds, 350+ configs, all outputs versioned in Git
- **Scale:** 6 DL architectures × multiple hyperparameter grids × 5 seeds = 378+ configurations

---

## 🔗 Related Projects

| Project | Description |
|---------|-------------|
| [Direction Forecasting BIST-BES](https://github.com/kuurtali/direction-forecasting-bist-bes) | Academic paper: ARIMA vs LSTM vs 1D-CNN on BIST & pension funds — majority class illusion |
| [ADAS Pricing Paradox](https://github.com/kuurtali/ADAS-Pricing-Paradox) | Actuarial pricing: 100K policies, Poisson + Gamma GLM — do ADAS vehicles cost less? |
| [VOL2 — ADAS Advanced](https://github.com/kuurtali/VOL2-ADAS-Pricing-Paradox) | Extended ADAS: 200K policies, Gini Index, Lift Charts, interaction terms |
| [Actuarial Shiny Dashboard](https://github.com/kuurtali/actuarial-analysis-w-shiny-and-glm) | Interactive risk scoring: Logistic GLM + R Shiny (AUC 0.828) |

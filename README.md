# MC-AWARE — Anti-Prediktif Davranışın Derin Öğrenme ile Tespiti

**TÜBİTAK 2209-A Lisans Araştırma Projesi (2026)**

**Yürütücü:** Mehmet Ali Kurt · **Danışman:** Dr. Övgücan Karadağ Erdemir · **Üniversite:** Hacettepe — Aktüerya Bilimleri

<p align="center">
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white" />
  <img src="https://img.shields.io/badge/Keras-D00000?style=for-the-badge&logo=Keras&logoColor=white" />
  <img src="https://img.shields.io/badge/Streamlit-FF4B4B?style=for-the-badge&logo=Streamlit&logoColor=white" />
  <img src="https://img.shields.io/badge/Plotly-3F4F75?style=for-the-badge&logo=plotly&logoColor=white" />
  <img src="https://img.shields.io/badge/Deep%20Learning-FF6F00?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Actuarial%20Science-brightgreen?style=for-the-badge" />
</p>

<p align="center">
  <a href="https://mcaware.streamlit.app">
    <img src="https://img.shields.io/badge/🚀_Canlı_Demo-10_Tab_Dashboard-brightgreen?style=for-the-badge" alt="Live Demo" />
  </a>
</p>

---

## 🔬 Proje Özeti

BIST (Borsa İstanbul) günlük yön tahmininde **6 farklı derin öğrenme mimarisi** ile **350+ konfigürasyon** test edildi. Tüm mimarilerde modellerin **rastgeleden daha kötü** tahmin yaptığı, ancak tahminleri **ters çevirince** rastgeleden **daha iyi** sonuç verdiği tespit edildi.

Bu **anti-prediktif davranış**, makro değişkenlerin (USD/TRY, petrol, faiz) eğitim ve test dönemleri arasındaki korelasyon kırılmasından kaynaklanmaktadır. Binom testi ile bu sonucun rastlantısal olma olasılığı **p ≈ 3×10⁻¹⁴** olarak hesaplanmıştır.

---

## 🚀 Canlı Dashboard (10 Tab)

**[mcaware.streamlit.app](https://mcaware.streamlit.app)** — 120 CSV dosyasından yüklenen gerçek deney sonuçları:

| Tab | İçerik | Veri Kaynağı |
|:---:|--------|-------------|
| 📊 | **Ana Bulgular** — Metrik kartlar, havuzlanmış confusion matrix, fold-bazlı analiz | `pooled_confusion_matrix.csv`, `confusion_by_fold.csv` |
| 🏗️ | **Mimari Karşılaştırma** — 7 mimari bar chart, McNemar heatmap, WF multi-arch ısı haritası | `CROSS_ARCH_SUMMARY.csv`, `McNEMAR.csv` |
| 📈 | **Walk-Forward** — 7-fold çizgi grafik, fold detay tablosu, fold özeti | `walkforward_RESULTS.csv`, `FOLD_SUMMARY.csv` |
| 🔬 | **BiLSTM Evrim** — v1 → v2a → v2b → v3 → v3b → v3c → attn_v6 gelişim süreci | 9 adet `*_SUMMARY.csv` |
| 🔍 | **Tahmin Analizi** — 10 varlık/mimari seçimi, ŷ histogram, CM, kümülatif doğruluk | 13 `*_PREDICTIONS.csv` |
| 🧪 | **Ablation** — Feature grup, tekli özellik, pencere boyutu ablasyonu | 3 `*_ablation_SUMMARY.csv` |
| 🌍 | **Cross-Market** — BIST vs NASDAQ, korelasyon kayması, holding/sigorta sektör analizi | `nasdaq_SUMMARY.csv`, `corr_*.csv` |
| 🗳️ | **Ensemble & Baseline** — Hard/soft voting, rule-based ML, 10 teknik indikatör | `ensemble_*.csv`, `rule_based_*.csv` |
| 📐 | **İstatistiksel Kanıtlar** — Mutual Information, label check, YHAT istatistikleri | `MI_SCORES.csv`, `LABEL_CHECK.csv` |
| 📊 | **Threshold & Diagnostics** — Eşik grid heatmap, seed raporu, YHAT dağılım | `THRESHOLD_GRID.csv`, `YHAT_STATS.csv` |

> **Not:** Dashboard'da hiçbir sahte/rastgele veri yoktur. Tüm grafikler ve tablolar `Sonuclar/` klasöründeki gerçek CSV dosyalarından yüklenir.

---

## 🔑 Temel Bulgular

| Bulgu | Detay |
|-------|-------|
| **MC Tuzağı Çözümü** | 105/105 konfigürasyonda MC=0 (class_weight + MC-Aware loss) |
| **Anti-Prediktif Davranış** | 103/105 konfigürasyonda flip > naive (p ≈ 3×10⁻¹⁴) |
| **Mimariden Bağımsız** | 6 DL mimarisi (BiLSTM, GRU, Conv1D, TCN, Transformer, SimpleRNN) + Ensemble + Attention — hepsi aynı örüntü |
| **Walk-Forward** | 7-fold temporal CV ile doğrulandı — dönemsel etki |
| **Mekanizma** | Makro korelasyon kırılması (USDTRY: train=0.91 → test=0.41) |
| **Cross-Market** | NASDAQ'ta normal davranış — etki gelişmekte olan piyasalara özgü |
| **Klasik ML** | Rule-based ve ML baseline'larda anti-prediktif davranış yok — sadece DL'de |
| **Feature Ablation** | Harici makro değişkenler çıkarılınca anti-prediktif davranış kayboluyor |

---

## 🧪 Deney Serileri (350+ Konfigürasyon)

| # | Deney | Açıklama | Konfigürasyon |
|---|-------|---------|--------------|
| 1 | BiLSTM v1–v6 | Model evrim süreci (6 major versiyon) | 9 × 15 = 135 |
| 2 | Multi-Architecture | 7 farklı DL mimarisi | 7 × 15 = 105 |
| 3 | Walk-Forward CV | 7-fold temporal doğrulama | 7 fold |
| 4 | Feature Ablation | full_13 vs no_ext_10 + tekli çıkarma | 5 grup × 3 seed |
| 5 | Input-Length | Pencere boyutu (2, 5, 10 gün) | 3 × 15 = 45 |
| 6 | Cross-Market | BIST THYAO vs NASDAQ AAPL | 4 konfigürasyon |
| 7 | Multi-Stock | BIST-3 (bankacılık) + BIST-5 (holding) + BIST-5 (sigorta) | 39 konfigürasyon |
| 8 | Ensemble | Hard + Soft Voting (6 mimari) | 8 sonuç |
| 9 | Rule-Based Baseline | DecisionTree, RF, LR, OneR | 12 sonuç |
| 10 | Teknik İndikatörler | SMA, EMA, RSI, MACD, BBand, Stoch, CCI, WilliamsR, ADX, ROC | 11 yöntem |
| 11 | Threshold Grid | Olasılık eşik optimizasyonu | 135 grid noktası |

---

## 📁 Proje Yapısı

```
00_Tubitak/
├── app.py                  # Streamlit dashboard (1014 satır, 10 tab)
├── requirements.txt        # Python bağımlılıkları
├── Docs/                   # Raporlar ve dokümanlar
│   ├── Dashboard/          # Eski HTML dashboard (arşiv)
│   ├── TUBITAK_2209A_Nihai_Rapor.txt
│   └── PROJECT_REPORT.txt
├── Kodlar/                 # R & Python deneyleri
│   ├── 01_prototypes/      # BiLSTM v1-v6, LSTM, multi-arch
│   ├── 02_ablation/        # Feature, IN_LEN, korelasyon
│   ├── 03_validation/      # Walk-forward, NASDAQ, multi-stock
│   ├── 04_baseline/        # Klasik ML ve Ensemble
│   ├── 05_diagnostic/      # MI, teşhis testleri
│   ├── 06_ek_deneyler/     # Sektörel karşılaştırma
│   └── FINAL_RELEASE/      # Nihai yayın paketi
├── Sonuclar/               # 120 CSV dosyası
│   ├── summaries/          # Deney özet tabloları
│   ├── predictions/        # Ham tahmin serileri
│   ├── diagnostics/        # İstatistiksel tanı verileri
│   └── thresholds/         # Eşik grid sonuçları
└── Gorseller/              # 33 yüksek çözünürlüklü grafik
```

---

## 🔧 Kurulum ve Çalıştırma

### Dashboard (Streamlit)
```bash
git clone https://github.com/kuurtali/Tubitak-2209A-MCAware.git
cd Tubitak-2209A-MCAware
pip install -r requirements.txt
streamlit run app.py
```

### Deneyleri Yeniden Üretme (R)
```bash
# R ve Keras/TensorFlow kurulu olmalıdır
source("install_packages.R")
Rscript Kodlar/FINAL_RELEASE/01_Sektorel_Karsilastirma_Sigorta.R
```

> **Not:** Model eğitimi donanıma bağlı olarak 45-60 dakika sürebilir. Çıktılar `Sonuclar/` klasörüne kaydedilir.

---

## 🇬🇧 English Summary

### About

This project investigates the **Majority Class (MC) trap** in deep learning models for daily stock direction prediction on BIST (Borsa Istanbul). Funded by **TÜBİTAK 2209-A** undergraduate research grant.

After solving the MC trap, we discovered that DL models exhibit **anti-predictive behavior** — systematically predicting the *opposite* direction — due to macroeconomic correlation breakdown between training and test periods.

### Key Results

| Finding | Detail |
|---------|--------|
| **MC Trap Solved** | 105/105 configs achieve MC=0 |
| **Anti-Predictive** | 103/105 configs: flip > naive (p ≈ 3×10⁻¹⁴) |
| **Architecture-Independent** | 6 DL architectures + Ensemble + Attention — all show same pattern |
| **Mechanism** | Macro-variable correlation breakdown (USDTRY: train 0.91 → test 0.41) |
| **Cross-Market** | NASDAQ shows normal behavior — effect is emerging-market specific |
| **Feature Ablation** | Removing macro variables eliminates anti-predictive behavior |

### Live Dashboard

**[mcaware.streamlit.app](https://mcaware.streamlit.app)** — 10-tab interactive dashboard with 64 real CSV data sources, 40+ charts, 20+ tables. Zero mock data.

---

## 🔗 İlgili Projeler

| Proje | Açıklama |
|-------|---------|
| [Direction Forecasting BIST-BES](https://github.com/kuurtali/direction-forecasting-bist-bes) | Akademik makale: ARIMA vs LSTM vs 1D-CNN — majority class illüzyonu |
| [VOL1 — ADAS Pricing Paradox](https://github.com/kuurtali/ADAS-Pricing-Paradox) | 100K poliçe, Poisson + Gamma GLM, temel ADAS fiyatlama analizi |
| [VOL2 — ADAS Pricing Paradox](https://github.com/kuurtali/VOL2-ADAS-Pricing-Paradox) | 200K poliçe, interaction terms, Gini Index, Lift Chart |
| [Actuarial Shiny Dashboard](https://github.com/kuurtali/actuarial-analysis-w-shiny-and-glm) | Logistic GLM + R Shiny interaktif risk skorlama (AUC 0.828) |

---

<p align="center">
  <i>Tüm sonuçlar gerçek deneylerden elde edilmiştir. Yatırım tavsiyesi değildir.</i><br>
  <b>TÜBİTAK 2209-A · Hacettepe Üniversitesi · 2026</b>
</p>

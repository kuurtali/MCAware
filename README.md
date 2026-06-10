# MC-AWARE — Anti-Prediktif Davranışın Derin Öğrenme ile Tespiti

**TÜBİTAK 2209-A Lisans Araştırma Projesi (2026)**

**Yürütücü:** Mehmet Ali Kurt · **Danışman:** Dr. Övgücan Karadağ Erdemir · **Üniversite:** Hacettepe — Aktüerya Bilimleri

<p align="center">
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white" />
  <img src="https://img.shields.io/badge/Keras-D00000?style=for-the-badge&logo=Keras&logoColor=white" />
  <img src="https://img.shields.io/badge/TensorFlow-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" />
  <img src="https://img.shields.io/badge/Streamlit-FF4B4B?style=for-the-badge&logo=Streamlit&logoColor=white" />
  <img src="https://img.shields.io/badge/Plotly-3F4F75?style=for-the-badge&logo=plotly&logoColor=white" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" />
</p>

<p align="center">
  <a href="https://mcaware.streamlit.app">
    <img src="https://img.shields.io/badge/Canlı_Demo-Dashboard_(12_Tab)-blue?style=for-the-badge" alt="Live Demo" />
  </a>
</p>

<p align="center">
  <code>30+ Deney</code> · <code>6 DL Mimarisi</code> · <code>27 Varlık</code> · <code>700+ Konfigürasyon</code> · <code>130 CSV</code> · <code>p < 0.0001</code>
</p>

---

## 🔬 Proje Özeti

BIST (Borsa İstanbul) günlük yön tahmininde **6 farklı derin öğrenme mimarisi** ile **700+ konfigürasyon** test edilmiştir. Tüm mimarilerde modellerin rastgeleden daha kötü tahmin yaptığı, ancak tahminlerin ters çevrilmesiyle rastgeleden daha iyi sonuç elde edildiği gözlemlenmiştir.

Bu **anti-prediktif davranış**, makro değişkenlerin (USD/TRY, petrol, faiz) eğitim ve test dönemleri arasındaki korelasyon kırılmasından kaynaklanmaktadır. 11 BIST hissesinden 5'inde (THYAO, PGSUS, HEKTS, SASA, KRDMD) sistematik anti-prediktif davranış tespit edilmiştir. **Bonferroni-düzeltilmiş p = 0.00012**.

---

## 📊 Canlı Dashboard

**[mcaware.streamlit.app](https://mcaware.streamlit.app)** — 130 CSV dosyasından yüklenen gerçek deney sonuçları:

| Tab | İçerik | Veri Kaynağı |
|:---:|--------|-------------|
| 📊 | **Ana Bulgular** — Metrik kartlar, confusion matrix, fold-bazlı analiz | `pooled_confusion_matrix.csv` |
| 🏗️ | **Mimari Karşılaştırma** — 7 mimari bar chart, McNemar heatmap | `CROSS_ARCH_SUMMARY.csv`, `McNEMAR.csv` |
| 📈 | **Walk-Forward** — 7-fold çizgi grafik, fold detay tablosu | `walkforward_RESULTS.csv` |
| 🔬 | **BiLSTM Evrim** — v1 → v3c → attn_v6 gelişim süreci | 9 adet `*_SUMMARY.csv` |
| 🔍 | **Tahmin Analizi** — ŷ histogram, CM, kümülatif doğruluk | 13 `*_PREDICTIONS.csv` |
| 🧪 | **Ablation** — Feature grup, tekli özellik, pencere boyutu | 3 `*_ablation_RESULTS.csv` |
| 🌍 | **Cross-Market** — BIST vs NASDAQ, sektör analizi | `nasdaq_RESULTS.csv`, `corr_*.csv` |
| 🗳️ | **Ensemble & Baseline** — Voting, rule-based ML, teknik indikatör | `ensemble_*.csv`, `rule_based_*.csv` |
| 📐 | **İstatistiksel Kanıtlar** — MI, label check, YHAT istatistikleri | `MI_SCORES.csv`, `LABEL_CHECK.csv` |
| 📊 | **Threshold & Diagnostics** — Eşik grid heatmap, seed raporu | `THRESHOLD_GRID.csv`, `YHAT_STATS.csv` |
| ⚔️ | **Karşılaştırma** — İki konfigürasyon arasında birebir metrik karşılaştırma | Tüm `OPTIMAL.csv` |
| 📷 | **Ek Görseller** — 15 yeni CSV-tabanlı analiz grafiği | 130 CSV'den üretilmiş |

> Dashboard'da sahte veri yoktur. Tüm çıktılar `Sonuclar/` klasöründeki CSV dosyalarından yüklenmektedir.

---

## 🔑 Temel Bulgular

| Bulgu | Detay |
|-------|-------|
| **MC Tuzağı Çözümü** | 700+ konfigürasyonda MC=0 (`class_weight` + MC-Aware loss) |
| **Anti-Prediktif Davranış** | THYAO 15/15 anti-prediktif (p < 0.0001), 4 hissede tam, 1 hissede güçlü |
| **11 Hisse Genellenebilirlik** | Havacılık + spekülatif + emtia sektörlerinde yaygın; bankacılık/otomotivde yok |
| **Mimariden Bağımsız** | BiLSTM, GRU, Conv1D, TCN, Transformer, SimpleRNN — 6 mimaride aynı örüntü |
| **Pencere Uzunluğu Etkisi** | IN_LEN ≤ 5 → anti-prediktif; IN_LEN = 10 → kayboluyor (temporal resolution) |
| **Walk-Forward v2** | 7-fold CV × 6 mimari × 3 seed — Fold 2 (COVID) ve Fold 7 (enflasyon) dönemlerinde tetikleniyor |
| **Mekanizma** | Makro korelasyon kırılması (USDTRY: train 0.91 → test 0.41) |
| **Makro Değişken Rolü** | USDTRY + Oil + TCMB çıkarılınca anti-prediktif tamamen kayboluyor |
| **Cross-Market** | NASDAQ'ta normal davranış — gelişmekte olan piyasaya özgü |
| **Klasik ML** | Rule-based baseline'larda anti-prediktif davranış yok — yalnızca DL'de |

---

## 🧪 Deney Serileri

| # | Deney | Açıklama | Konfigürasyon |
|---|-------|---------|--------------|
| 1 | BiLSTM v1–v6 | Model evrim süreci (6 versiyon) | 9 × 15 = 135 |
| 2 | Multi-Architecture | 6 DL mimarisi karşılaştırma | 7 × 15 = 105 |
| 3 | Walk-Forward CV v2 | 7-fold temporal CV × 6 mimari × 3 seed (val_data düzeltilmiş) | 126 |
| 4 | Feature Ablation | full_13 vs no_ext_10 + tekli çıkarma | 5 grup × 3 seed |
| 5 | IN_LEN Ablation v2 | Pencere boyutu (2, 5, 10 gün) — OUT_LEN=3, gerçek TCMB | 3 × 15 = 45 |
| 6 | Cross-Market | BIST THYAO vs NASDAQ AAPL | 4 |
| 7 | Multi-Stock | BIST-3 (banka) + BIST-5 (holding) + BIST-5 (sigorta) + BIST-11 (makro) | 204 |
| 8 | Ensemble | Hard + Soft Voting (6 mimari) | 8 |
| 9 | Rule-Based Baseline | DecisionTree, RF, LR, OneR × 3 varlık | 12 |
| 10 | Teknik İndikatörler | SMA, EMA, RSI, MACD, BBand, Stoch, CCI, WilliamsR, ADX, ROC | 11 |
| 11 | Threshold Grid | Olasılık eşik optimizasyonu (0.30–0.70) | 135 |

---

## 🏛️ Test Edilen Varlıklar (27)

| Grup | Varlıklar | Anti-Prediktif? |
|------|-----------|----------------|
| **BIST — Havacılık** | THYAO, PGSUS | ✅ TAM (15/15) |
| **BIST — Spekülatif** | SASA, HEKTS | ✅ TAM (15/15) |
| **BIST — Emtia/Demir-Çelik** | KRDMD | ✅ GÜÇLÜ (13/15) |
| **BIST — Otomotiv/Ticaret** | FROTO, DOAS | ❌ Normal |
| **BIST — Bankacılık** | YKBNK, ISCTR, AKBNK, GARAN | ❌ Normal (Naive üstü) |
| **BIST — Çeşitli** | TAVHL, KOZAL | ➖ Nötr |
| **BIST — Sigorta** | AGESA, AKGRT, ANSGR, RAYSG, TURSG | (Sektörel test) |
| **BIST — Holding** | ALARK, DOHOL, ENKAI, KCHOL, SAHOL | (Sektörel test) |
| **NASDAQ** | AAPL | ❌ Normal |
| **BES Fonları** | ALZ, AZS, AMZ | (Fon testi) |

---

## 📁 Proje Yapısı

```
Tubitak/
├── app.py                  # Streamlit dashboard (12 tab, TR/EN)
├── requirements.txt        # Python bağımlılıkları
├── Dockerfile              # Docker container
├── README.md               # Bu dosya
├── Kodlar/                 # 59 kod dosyası (R + Python)
│   ├── 01_prototypes/      # BiLSTM v1-v6, multi-arch (12)
│   ├── 02_ablation/        # Feature, IN_LEN, korelasyon (5)
│   ├── 03_validation/      # Walk-forward, NASDAQ, multi-stock (5)
│   ├── 04_baseline/        # Klasik ML ve Ensemble (4)
│   ├── 05_diagnostic/      # MI, teşhis testleri (2)
│   ├── 06_ek_deneyler/     # Sektörel karşılaştırma (5)
│   └── 07_araclar/         # Python araçları, rapor üretici (26)
├── Sonuclar/               # 130 CSV dosyası
│   ├── summaries/   (71)   # Deney özet tabloları
│   ├── predictions/ (19)   # Ham tahmin serileri
│   ├── diagnostics/ (26)   # İstatistiksel tanı verileri
│   └── thresholds/  (14)   # Eşik grid sonuçları
├── Gorseller/              # 62 makale kalitesinde grafik (PNG)
└── Docs/                   # TÜBİTAK raporu, kişisel rapor, şablonlar
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

### Docker
```bash
docker build -t mcaware .
docker run -p 8501:8501 mcaware
```

### Deneyleri Yeniden Üretme (R)
```bash
Rscript Kodlar/01_prototypes/mcaware_prototype_BiLSTM_v3_THYAO.R
```

> Model eğitimi donanıma bağlı olarak 45-60 dakika sürebilir.

> **Not:** R deneyleri `ALZ_AZS_AMZ_Haftalik.xlsx` veri dosyasını gerektirir. Bu dosya gizlilik nedeniyle repoya dahil edilmemiştir.

---

## 🇬🇧 English Summary

This project investigates the **Majority Class (MC) trap** in deep learning models for daily stock direction prediction on BIST (Borsa Istanbul). Funded by **TÜBİTAK 2209-A** undergraduate research grant.

After solving the MC trap with `class_weight=balanced`, we discovered that DL models exhibit **anti-predictive behavior** — systematically predicting the *opposite* direction — due to macroeconomic correlation breakdown between training and test periods.

| Finding | Detail |
|---------|--------|
| **MC Trap Solved** | 700+ configs achieve MC=0 |
| **Anti-Predictive** | 5/11 BIST stocks anti-predictive; THYAO 15/15 (p < 0.0001) |
| **Architecture-Independent** | 6 DL architectures — all show same pattern in walk-forward |
| **Window Length** | IN_LEN ≤ 5 → anti-predictive; IN_LEN = 10 → normal |
| **Mechanism** | Macro-variable correlation breakdown (USDTRY: train 0.91 → test 0.41) |
| **Cross-Market** | NASDAQ shows normal behavior — emerging-market specific |
| **Feature Ablation** | Removing macro variables completely eliminates anti-predictive behavior |

**Live Dashboard:** [mcaware.streamlit.app](https://mcaware.streamlit.app) — 12 tabs, 130 CSV sources, 62 visuals, no mock data.

---

## 🔗 İlgili Projeler

| Proje | Açıklama |
|-------|---------|
| [Direction Forecasting BIST-BES](https://github.com/kuurtali/direction-forecasting-bist-bes) | ARIMA vs LSTM vs 1D-CNN — majority class illüzyonu |
| [VOL1 — ADAS Pricing Paradox](https://github.com/kuurtali/ADAS-Pricing-Paradox) | 100K poliçe, Poisson + Gamma GLM |
| [VOL2 — ADAS Pricing Paradox](https://github.com/kuurtali/VOL2-ADAS-Pricing-Paradox) | 200K poliçe, interaction terms, Gini Index |
| [Actuarial Shiny Dashboard](https://github.com/kuurtali/actuarial-analysis-w-shiny-and-glm) | Logistic GLM + R Shiny risk skorlama |

---

<p align="center">
  <i>Tüm sonuçlar gerçek deneylerden elde edilmiştir. Yatırım tavsiyesi değildir.</i><br>
  <b>TÜBİTAK 2209-A · Hacettepe Üniversitesi · 2026</b>
</p>

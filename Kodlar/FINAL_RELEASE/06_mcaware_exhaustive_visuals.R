# ===========================================================================
# MC-AWARE - TUM OLASI GRAFIKLERI CIZME (EXHAUSTIVE VISUALS)
# Amac: Makale icin eklenebilecek tum ekstra istatistiksel grafikler
# NOT: RStudio karakter kodlamasi hatasini onlemek adina ASCII (Turkce karaktersiz) kullanilmistir.
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- here::here()
setwd(WORKDIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(ggplot2)
})

if (!dir.exists("Gorseller")) { dir.create("Gorseller", recursive = TRUE) }

# ---------------------------------------------------------------------------
# GRAFIK 6: 6-MIMARI PERFORMANS KIYASLAMASI (BAR GRAFIGI)
# ---------------------------------------------------------------------------
# OZET.txt Bolum 3.2
arch_data <- data.frame(
  Mimari = c("GRU", "Conv1D", "BiLSTM", "TCN", "Transformer", "SimpleRNN"),
  Acc = c(0.389, 0.394, 0.396, 0.411, 0.429, 0.449),
  Acc_Flip = c(0.611, 0.606, 0.604, 0.589, 0.571, 0.551)
)
arch_data$Naive <- 0.518

arch_long <- arch_data %>% pivot_longer(cols=c("Acc", "Acc_Flip"), names_to="Tip", values_to="Skor")

p_arch <- ggplot(arch_long, aes(x=reorder(Mimari, Skor), y=Skor, fill=Tip)) +
  geom_bar(stat="identity", position="dodge", color="black", alpha=0.9) +
  geom_hline(aes(yintercept=0.518), color="red", linetype="dashed", linewidth=1.2) +
  scale_fill_manual(values=c("Acc"="#e41a1c", "Acc_Flip"="#4daf4a"), labels=c("Duz Tahmin (Hatali)", "Ters Cevrilmis Tahmin")) +
  theme_minimal(base_size=14) +
  labs(
    title="6 Farkli Derin Ogrenme Mimarisi: Sistematik Hata (Anti-Prediktiflik)",
    subtitle="Kirmizi kesik cizgi (Rastgele Tahmin - Naive). Hicbir model duz tahminde rastgeleligi gecemezken,\nhepsi ters cevrildiginde basarili olmaktadir.",
    x="Mimari", y="Dogruluk (Accuracy)"
  ) + coord_flip() + theme(legend.position="bottom", legend.title=element_blank())

ggsave("Gorseller/06_Mimari_Kiyaslama.png", p_arch, width=10, height=6, dpi=300)
cat("Grafik 6 olusturuldu: Gorseller/06_Mimari_Kiyaslama.png\n")

# ---------------------------------------------------------------------------
# GRAFIK 7: WALK-FORWARD CV (ZAMAN ICINDE TUTARSIZLIK) CIZGI GRAFIGI
# ---------------------------------------------------------------------------
# 7 Fold verisi (OZET.txt Bolum 10.2: 3/7 Fold'da anti-prediktif)
wf_data <- data.frame(
  Fold = paste0("Fold ", 1:7),
  AntiPredictive = c(TRUE, FALSE, FALSE, TRUE, FALSE, TRUE, FALSE),
  Flip_Acc = c(0.56, 0.48, 0.51, 0.58, 0.49, 0.61, 0.50),
  Naive = c(0.52, 0.53, 0.50, 0.52, 0.54, 0.55, 0.51)
)

p_wf <- ggplot(wf_data, aes(x=Fold, group=1)) +
  geom_line(aes(y=Flip_Acc, color="Ters Tahmin Basarisi"), linewidth=1.5) +
  geom_line(aes(y=Naive, color="Rastgele (Naive) Basari"), linewidth=1.5, linetype="dashed") +
  geom_point(aes(y=Flip_Acc), size=4) +
  scale_color_manual(values=c("Ters Tahmin Basarisi"="#377eb8", "Rastgele (Naive) Basari"="#e41a1c")) +
  theme_minimal(base_size=14) +
  labs(
    title="Walk-Forward Capraz Dogrulama: Hatanin Rejim Bagimliligi",
    subtitle="Ters tahminin basarisi zaman icinde tutarsizdir. Bu durum hatanin 'donemsel' (Concept Drift) olduguna isaret eder.",
    x="", y="Dogruluk"
  ) + theme(legend.position="bottom", legend.title=element_blank())

ggsave("Gorseller/07_WalkForward_Tutarsizlik.png", p_wf, width=10, height=6, dpi=300)
cat("Grafik 7 olusturuldu: Gorseller/07_WalkForward_Tutarsizlik.png\n")

# ---------------------------------------------------------------------------
# GRAFIK 8: VARLIK-PIYASA HASSASIYET MATRISI (HEATMAP)
# ---------------------------------------------------------------------------
# BIST THYAO, BIST GARAN, NASDAQ AAPL Kontrasti
# Heatmap icin sayisal temsiliyet
heat_df <- data.frame(
  Varlik = factor(c("THYAO (BIST)", "GARAN (BIST)", "AAPL (NASDAQ)")),
  Drift_Siddeti = c(0.60, 0.37, 0.93), # Mutlak korelasyon degisimi (Temsili/Ozet)
  Hata_Var = c(1, 0, 0)
)

p_heat <- ggplot(heat_df, aes(x="Anti-Prediktif Hata", y=Varlik, fill=as.factor(Hata_Var))) +
  geom_tile(color="white", linewidth=1) +
  geom_text(aes(label=ifelse(Hata_Var==1, "SISTEMATIK HATA VAR", "HATA YOK (Rastgele)")), color="white", size=5, fontface="bold") +
  scale_fill_manual(values=c("0"="#999999", "1"="#e41a1c")) +
  theme_minimal(base_size=14) +
  labs(
    title="Piyasa ve Mikro-Yapi Sinirlamalari",
    subtitle="Korelasyon kirilmasi her varlikta olsa da, Sistematik Hata yalnizca kirilgan BIST hisselerinde olusur.",
    x="", y=""
  ) + theme(legend.position="none")

ggsave("Gorseller/08_Piyasa_Hassasiyet_Heatmap.png", p_heat, width=9, height=4, dpi=300)
cat("Grafik 8 olusturuldu: Gorseller/08_Piyasa_Hassasiyet_Heatmap.png\n")

# ---------------------------------------------------------------------------
# GRAFIK 9: TEMSILI ROC EGRISI (ANTI-PREDIKTIF BOLGE)
# ---------------------------------------------------------------------------
# Anti-prediktif bir modelin ROC egrisi diyagonalin ALTINDA (AUC < 0.5) kalir.
roc_data <- data.frame(
  FPR = seq(0, 1, length.out=100)
)
roc_data$TPR_Random <- roc_data$FPR
# Anti-prediktif (Kotu) Model (AUC ~ 0.40)
roc_data$TPR_Anti <- roc_data$FPR^1.5 
# Cevrilmis (Iyi) Model (AUC ~ 0.60)
roc_data$TPR_Flip <- roc_data$FPR^0.66

roc_long <- roc_data %>% pivot_longer(cols=c("TPR_Anti", "TPR_Flip", "TPR_Random"), names_to="Model", values_to="TPR")

p_roc <- ggplot(roc_long, aes(x=FPR, y=TPR, color=Model, linetype=Model)) +
  geom_line(linewidth=1.5) +
  scale_color_manual(values=c("TPR_Anti"="#e41a1c", "TPR_Flip"="#4daf4a", "TPR_Random"="black")) +
  scale_linetype_manual(values=c("TPR_Anti"="solid", "TPR_Flip"="solid", "TPR_Random"="dashed")) +
  theme_minimal(base_size=14) +
  labs(
    title="Anti-Prediktif (Ters Yonlu) Modellerin ROC Analizi (Illusrastasyon)",
    subtitle="Kirmizi egri diyagonalin altindadir (AUC < 0.5).\nBu durum, modelin ogrendigini ancak testte tam ters yone uyguladigini gosterir.",
    x="False Positive Rate (FPR)", y="True Positive Rate (TPR)"
  ) + theme(legend.position="none")

ggsave("Gorseller/09_AntiPredictive_ROC_Curve.png", p_roc, width=9, height=6, dpi=300)
cat("Grafik 9 olusturuldu: Gorseller/09_AntiPredictive_ROC_Curve.png\n")

cat("\nTUM EKSTRA GRAFIKLER (EXHAUSTIVE VISUALS) BASARIYLA TAMAMLANDI.\n")

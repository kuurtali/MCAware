# ===========================================================================
# MC-AWARE � G�RSELLE�T�RME VE RAPORLAMA SCR�PT�
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

# 1. Verilerin Y�klenmesi
sigorta <- read.csv(file.path(here::here(), "Sonuclar", "summaries", "mcaware_bist5_sigorta_SUMMARY.csv"))
sigorta$Sector <- "Sigorta (Kirilgan)"

holding <- read.csv(file.path(here::here(), "Sonuclar", "summaries", "mcaware_bist5_holding_SUMMARY.csv"))
holding$Sector <- "Holding (Dagitik)"

df <- dplyr::bind_rows(sigorta, holding)

# Ters Sinyal G�c�: (Modelin Ters Tahmin Ba�ar�s� - Rastgele Tahmin Ba�ar�s�)
# E�er bu de�er 0'dan b�y�kse, model RASTGELEL�KTEN SAPIP S�STEMAT�K HATA (Ters Sinyal) veriyor demektir.
df$Anti_Predictive_Gap <- df$mean_flip - df$naive

# 2. Grafik 1: Sekt�rel K�r�lganl�k K�yaslamas�
p1 <- ggplot(df, aes(x = reorder(ticker, Anti_Predictive_Gap), y = Anti_Predictive_Gap, fill = Sector)) +
  geom_bar(stat = "identity", color = "black", alpha = 0.8) +
  coord_flip() +
  scale_fill_manual(values = c("Sigorta (Kirilgan)" = "#d73027", "Holding (Dagitik)" = "#4575b4")) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black", linewidth = 1.2) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Sekt�rel Makro-K�r�lganl���n Yapay Zeka Hatalar�na Etkisi (Y5 Hipotezi)",
    subtitle = "De�er > 0: Sistematik Ters Tahmin (Anti-Prediktiflik). De�er < 0: Rastgelelik",
    x = "Hisseler",
    y = "Ters Sinyal G�c� (Flip Acc - Naive Acc)"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    legend.position = "bottom",
    legend.title = element_blank()
  )

ggsave("Gorseller/01_Sektorel_Kiyaslama_Bar.png", p1, width = 11, height = 7, dpi = 300)
cat("Grafik 1 olusturuldu: Gorseller/01_Sektorel_Kiyaslama_Bar.png\n")

# 3. Grafik 2: MC Tuza��n�n ��z�ld���n� G�steren Da��l�m
# Sens ve Spec 0 ise MC'dir. Bizde MC'nin asildigini gostermek icin 
# Hisselerin cogunluk sinifi secme bias'i (Acc vs Flip Acc) cizilebilir.
p2 <- ggplot(df, aes(x = naive, y = mean_flip, color = Sector, label = ticker)) +
  geom_point(size = 5, alpha = 0.8) +
  geom_text(vjust = -1, size = 4) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "red", linewidth = 1) +
  scale_color_manual(values = c("Sigorta (Kirilgan)" = "#d73027", "Holding (Dagitik)" = "#4575b4")) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Model Tahmin G�c� vs Rastgele Tahmin (Naive)",
    subtitle = "K�rm�z� �izginin �ST�NDE kalanlar rastgelelikten sap�p S�STEMAT�K YANILANLARDIR.",
    x = "Rastgele Tahmin Do�rulu�u (Naive Baseline)",
    y = "Ters �evrilmi� Tahmin Do�rulu�u (Flip Accuracy)"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    legend.position = "bottom",
    legend.title = element_blank()
  )

ggsave("Gorseller/02_Anti_Prediktif_Scatter.png", p2, width = 10, height = 7, dpi = 300)
cat("Grafik 2 olusturuldu: Gorseller/02_Anti_Prediktif_Scatter.png\n")

cat("\nG�RSELLE�T�RME BA�ARIYLA TAMAMLANDI.\n")

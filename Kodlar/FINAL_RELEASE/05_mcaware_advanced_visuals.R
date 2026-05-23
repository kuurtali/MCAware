# ===========================================================================
# MC-AWARE — GENİŞLETİLMİŞ GÖRSELLEŞTİRME (AKSIYON 5)
# Amaç: TÜBİTAK Jüri raporunu destekleyecek 3 gelişmiş grafiğin çizilmesi
# ===========================================================================

WORKDIR <- "C:/Users/Kurt/Desktop/Proje/00_Tubitak"
setwd(WORKDIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(ggplot2)
  library(tidyr)
})

# Çıktı klasörünün olduğundan emin ol
if (!dir.exists("Gorseller")) { dir.create("Gorseller", recursive = TRUE) }

# ---------------------------------------------------------------------------
# GRAFİK 3: KORELASYON KIRILMASI (CONCEPT DRIFT) SLOPE CHART
# ---------------------------------------------------------------------------
# Veriler: OZET.txt Bölüm 4.2'den (THYAO Korelasyon Kırılması)
corr_data <- data.frame(
  Variable = c("USDTRY", "Oil (Petrol)", "TCMB Faizi"),
  Train_Cor = c(0.908, 0.414, 0.194),
  Test_Cor = c(0.412, -0.148, 0.311)
)

# Plot için uzun formata çevir
corr_long <- corr_data %>%
  pivot_longer(cols = c("Train_Cor", "Test_Cor"), names_to = "Period", values_to = "Correlation") %>%
  mutate(Period = factor(Period, levels = c("Train_Cor", "Test_Cor"), labels = c("Eğitim Dönemi (Train)", "Test Dönemi (Test)")))

p_slope <- ggplot(corr_long, aes(x = Period, y = Correlation, group = Variable, color = Variable)) +
  geom_line(linewidth = 2, alpha = 0.8) +
  geom_point(size = 5) +
  geom_text(aes(label = round(Correlation, 2)), vjust = -1.5, size = 5, fontface = "bold") +
  theme_minimal(base_size = 14) +
  scale_color_manual(values = c("USDTRY" = "#1b9e77", "Oil (Petrol)" = "#d95f02", "TCMB Faizi" = "#7570b3")) +
  labs(
    title = "Makroekonomik Korelasyon Kırılması (Concept Drift)",
    subtitle = "Özellikle Petrol'ün yön değiştirmesi ve Dolar'ın korelasyon yitirmesi model ezberini bozmuştur.",
    x = "",
    y = "Korelasyon Katsayısı (r)"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    legend.position = "bottom",
    legend.title = element_blank()
  )

ggsave("Gorseller/03_Correlation_Drift_Slope.png", p_slope, width = 9, height = 7, dpi = 300)
cat("Grafik 3 oluşturuldu: Gorseller/03_Correlation_Drift_Slope.png\n")


# ---------------------------------------------------------------------------
# GRAFİK 4: FEATURE ABLATION (DEĞİŞKEN ÇIKARMA) BAR GRAFİĞİ
# ---------------------------------------------------------------------------
# Veriler: OZET.txt Bölüm 4.1'den
ablation_data <- data.frame(
  Feature_Set = factor(
    c("Tam Set (13 Değişken)", "USDTRY Çıkarıldı", "Petrol Çıkarıldı", "TCMB Faizi Çıkarıldı", "Makro Değişkenler Çıkarıldı (10 Değişken)"),
    levels = c("Tam Set (13 Değişken)", "USDTRY Çıkarıldı", "Petrol Çıkarıldı", "TCMB Faizi Çıkarıldı", "Makro Değişkenler Çıkarıldı (10 Değişken)")
  ),
  Flip_Wins = c(15, 3, 3, 3, 0),
  Total_Configs = c(15, 3, 3, 3, 15)
)

ablation_data$Ratio <- ablation_data$Flip_Wins / ablation_data$Total_Configs

p_ablation <- ggplot(ablation_data, aes(x = Feature_Set, y = Ratio, fill = Ratio)) +
  geom_bar(stat = "identity", color = "black") +
  scale_fill_gradient(low = "#fee0d2", high = "#de2d26") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  coord_flip() +
  theme_minimal(base_size = 14) +
  labs(
    title = "Feature Ablation: Makro Şokların Hata Üzerindeki Etkisi",
    subtitle = "Tüm makro-kırılgan değişkenler silindiğinde Ters Tahmin (Anti-Prediktif) hatası SIFIRLANMAKTADIR.",
    x = "",
    y = "Ters Tahmin Yapan Model Oranı (%)"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    legend.position = "none"
  )

ggsave("Gorseller/04_Feature_Ablation_Bar.png", p_ablation, width = 10, height = 6, dpi = 300)
cat("Grafik 4 oluşturuldu: Gorseller/04_Feature_Ablation_Bar.png\n")


# ---------------------------------------------------------------------------
# GRAFİK 5: MC TUZAĞI ÇÖZÜM BULGUSU (SENSITIVITY VS SPECIFICITY)
# ---------------------------------------------------------------------------
# Normalde MC tuzağına düşen bir modelde Sensitivity (Sens) veya Specificity (Spec) 0 olur.
# Bizim çözdüğümüz mimarilerde ikisi de 0'dan büyüktür (gerçek karar vericilerdir).
mc_data <- data.frame(
  Model_Tipi = c("Eski Yöntem (MC Tuzağı)", "Yeni Yöntem (MC-Aware Custom Loss)"),
  Sensitivite = c(1.00, 0.45),
  Spesifisite = c(0.00, 0.35)
)

mc_long <- mc_data %>%
  pivot_longer(cols = c("Sensitivite", "Spesifisite"), names_to = "Metric", values_to = "Score")

p_mc <- ggplot(mc_long, aes(x = Model_Tipi, y = Score, fill = Metric)) +
  geom_bar(stat = "identity", position = "dodge", color = "black", alpha=0.9) +
  scale_fill_manual(values = c("Sensitivite" = "#4daf4a", "Spesifisite" = "#984ea3")) +
  geom_hline(yintercept = 0, color = "black", linewidth = 1) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Majority Class (Sınıf Dengesizliği) Tuzağının Aşılması",
    subtitle = "Eski yöntemde model sadece tek sınıfı bilirken (Spec=0); yeni yöntemde model her iki sınıfa da karar üretebilmektedir.",
    x = "",
    y = "Metrik Skoru"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    legend.position = "bottom",
    legend.title = element_blank()
  )

ggsave("Gorseller/05_MC_Tuzagi_Cozumu.png", p_mc, width = 9, height = 6, dpi = 300)
cat("Grafik 5 oluşturuldu: Gorseller/05_MC_Tuzagi_Cozumu.png\n")

cat("\nGENİŞLETİLMİŞ GÖRSELLEŞTİRME PAKETİ (AKSIYON 5) BAŞARIYLA TAMAMLANDI.\n")

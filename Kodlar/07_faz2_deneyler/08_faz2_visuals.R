# 08_faz2_visuals.R
# Faz 2 ek deneyleri (E2, B14) icin gorsel uretimi

suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tidyr))

cat("Faz 2 gorselleri uretiliyor...\n")

WORKDIR <- "C:/Users/Kurt/Desktop/Proje/00_Tubitak"
OUTDIR <- file.path(WORKDIR, "Gorseller")
setwd(WORKDIR)

# --- 1. Majority Voting vs Classic ML (E2) ---
# Verileri manuel aliyoruz (daha onceden hesaplanan E2 ve I.16 sonuclari)
df_e2 <- data.frame(
  Method = c("DL Naive Baseline", "Random Forest", "Logistic Regression", "Majority Rules (10-ind)"),
  Accuracy = c(0.518, 0.510, 0.515, 0.645),
  Type = c("Baseline", "Classic ML", "Classic ML", "Rule-Based Voting")
)

df_e2$Method <- factor(df_e2$Method, levels = c("DL Naive Baseline", "Random Forest", "Logistic Regression", "Majority Rules (10-ind)"))

p1 <- ggplot(df_e2, aes(x = Method, y = Accuracy, fill = Type)) +
  geom_bar(stat = "identity", width = 0.6, color="black") +
  geom_hline(yintercept = 0.518, linetype = "dashed", color = "red", size=1) +
  geom_text(aes(label = sprintf("%.3f", Accuracy)), vjust = -0.5, size=5, fontface="bold") +
  scale_fill_manual(values = c("Baseline" = "#94a3b8", "Classic ML" = "#3b82f6", "Rule-Based Voting" = "#10b981")) +
  theme_minimal(base_size = 14) +
  labs(title = "E2: Majority Rules (10-ind) vs Classic ML Modelleri",
       subtitle = "10 klasik gostergenin cogunluk oylamasi (Rule-Based) Naive'i belirgin bicimde geciyor",
       x = "Yontem", y = "Dogruluk (Accuracy)") +
  theme(legend.position = "none",
        plot.title = element_text(face="bold", hjust=0.5),
        plot.subtitle = element_text(hjust=0.5)) +
  coord_cartesian(ylim=c(0.4, 0.7))

ggsave(file.path(OUTDIR, "19_Majority_Voting_vs_ML.png"), p1, width = 9, height = 6, dpi = 300)
cat("[OK] 19_Majority_Voting_vs_ML.png\n")

# --- 2. Pooled Confusion Matrix (B14) ---
# TP: 367, FP: 287, TN: 337, FN: 409
cm_df <- data.frame(
  Prediction = factor(c("UP", "UP", "DOWN", "DOWN"), levels=c("DOWN", "UP")),
  Actual = factor(c("UP", "DOWN", "UP", "DOWN"), levels=c("DOWN", "UP")),
  Freq = c(367, 287, 409, 337)
)

p2 <- ggplot(cm_df, aes(x = Actual, y = Prediction, fill = Freq)) +
  geom_tile(color = "white", size=1) +
  geom_text(aes(label = Freq), size = 10, color = "white", fontface="bold") +
  scale_fill_gradient(low = "#3b82f6", high = "#1e1b4b") +
  theme_minimal(base_size = 16) +
  labs(title = "B14: Walk-Forward Pooled Confusion Matrix",
       subtitle = "Tum 7 fold'un birlestirilmis sonuclari (N = 1400)",
       x = "Gercek Yon (Actual)", y = "Tahmin Edilen Yon (Prediction)") +
  theme(legend.position = "none",
        plot.title = element_text(face="bold", hjust=0.5),
        plot.subtitle = element_text(hjust=0.5),
        panel.grid = element_blank())

ggsave(file.path(OUTDIR, "20_Pooled_Confusion_Matrix.png"), p2, width = 7, height = 6, dpi = 300)
cat("[OK] 20_Pooled_Confusion_Matrix.png\n")

cat("Tum gorseller basariyla uretildi.\n")

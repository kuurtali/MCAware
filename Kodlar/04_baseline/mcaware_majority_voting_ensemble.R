# ===========================================================================
# MC-AWARE — MAJORITY VOTING ENSEMBLE (ADIM I.14)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   6 mimari (BiLSTM, GRU, SimpleRNN, Conv1D, TCN, Transformer) tahminlerini
#   COGUNLUK OYU (majority voting) ile birlestir. "Tek model anti-prediktif
#   ama topluluk Naive'i gecer mi?" sorusunu test eder.
#
#   PDF taslagindaki "Majority Rules baseline" maddesinin somut karsiligi.
#
# NEDEN ANLAMLI:
#   McNemar testi 6 mimarinin COGUNLUKLA AYNI hatalari yaptigini gosterdi
#   (n.s. cogunlukta). Eger gercekten ayni yondeyse, ensemble da ayni
#   sekilde anti-prediktif olur → hipotezimizi GUCLENDIRIR.
#   Eger ensemble Naive'i geciyorsa → mimari cesitliligi sinyali yakaliyor
#   demek → Yorum 3'u ZAYIFLATIR ama operasyonel kazanc.
#
# YONTEM:
#   1. 6 mimari PREDICTIONS.csv'lerini yukle
#   2. Her test sample'i icin: 6 modelin (lambda x seed = 15 config'in
#      ortalamasi) tahmin olasiligi → cogunluk yonu
#   3. Aynileri Acc/Spec/Sens/MC/flip metrikleri
#   4. Iki strateji:
#      (a) HARD VOTING: her model thr=0.5 ile sinif, sonra cogunluk
#      (b) SOFT VOTING: 6 modelin yhat ortalamasi, sonra thr=0.5
#
# YENI MODEL EGITIMI YOK — sadece mevcut CSV'leri okuyor.
# Calistirma: RStudio → Ctrl+Shift+S → ~30 saniye → 3 CSV
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- "here::here()"
OUTDIR  <- WORKDIR
setwd(WORKDIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

cat("\n========================================================================\n")
cat("MC-AWARE — MAJORITY VOTING ENSEMBLE (ADIM I.14)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Mimariler: BiLSTM (v3b), GRU, SimpleRNN, Conv1D, TCN, Transformer\n")
cat("========================================================================\n\n")

# --- 1. PREDICTIONS.csv dosyalarini yukle ---
arch_files <- list(
  BiLSTM      = "mcaware_BiLSTM_v3b_window_PREDICTIONS.csv",
  GRU         = "mcaware_multi_arch_GRU_PREDICTIONS.csv",
  SimpleRNN   = "mcaware_multi_arch_SimpleRNN_PREDICTIONS.csv",
  Conv1D      = "mcaware_multi_arch_Conv1D_PREDICTIONS.csv",
  TCN         = "mcaware_multi_arch_TCN_PREDICTIONS.csv",
  Transformer = "mcaware_multi_arch_Transformer_PREDICTIONS.csv"
)

cat("CSV'ler yukleniyor:\n")
arch_preds <- list()
for (arch in names(arch_files)) {
  fp <- file.path(WORKDIR, arch_files[[arch]])
  if (!file.exists(fp)) {
    cat(sprintf("  HATA: %s bulunamadi: %s\n", arch, fp))
    stop("PREDICTIONS dosyalari eksik.")
  }
  df <- read.csv(fp, stringsAsFactors = FALSE)
  df$arch <- arch
  arch_preds[[arch]] <- df
  cat(sprintf("  %-12s: %d satir\n", arch, nrow(df)))
}

# --- 2. Test setindeki tahminleri birlestir ---
all_test <- do.call(rbind, arch_preds) %>%
  filter(set == "test") %>%
  select(arch, lambda, seed, sample_id, yhat, y_true)

cat(sprintf("\nToplam test tahmini: %d satir (6 mimari x 15 config x 305 sample)\n",
            nrow(all_test)))

# --- 3. Her mimari icin sample basina yhat ortalamasi (15 config bos seed avg) ---
arch_mean <- all_test %>%
  group_by(arch, sample_id, y_true) %>%
  summarise(yhat_arch = mean(yhat, na.rm = TRUE), .groups = "drop")

cat(sprintf("Mimari basina sample-ortalama yhat: %d satir\n", nrow(arch_mean)))

# --- 4. Hard voting: her mimari thr=0.5 sinif, sonra cogunluk ---
hard_votes <- arch_mean %>%
  mutate(pred_arch = as.integer(yhat_arch > 0.5)) %>%
  group_by(sample_id, y_true) %>%
  summarise(
    n_votes_up = sum(pred_arch),
    n_archs    = dplyr::n(),
    pred_hard  = as.integer(n_votes_up > n_archs / 2),
    .groups    = "drop"
  )

# --- 5. Soft voting: 6 mimari yhat ortalama, sonra thr=0.5 ---
soft_votes <- arch_mean %>%
  group_by(sample_id, y_true) %>%
  summarise(
    yhat_soft = mean(yhat_arch, na.rm = TRUE),
    pred_soft = as.integer(yhat_soft > 0.5),
    .groups   = "drop"
  )

# --- 6. Tek tek mimari Acc + ensemble Acc ---
naive_acc <- max(mean(arch_mean$y_true), 1 - mean(arch_mean$y_true))
naive_acc <- mean(soft_votes$y_true == as.integer(mean(soft_votes$y_true) > 0.5))
cat(sprintf("\nNaive baseline (test): %.4f\n", naive_acc))

# Metric helper
compute <- function(y_true, y_pred) {
  tp <- sum(y_pred == 1 & y_true == 1)
  tn <- sum(y_pred == 0 & y_true == 0)
  fp <- sum(y_pred == 1 & y_true == 0)
  fn <- sum(y_pred == 0 & y_true == 1)
  n  <- length(y_true)
  acc  <- (tp + tn) / n
  sens <- if ((tp+fn) > 0) tp/(tp+fn) else NA_real_
  spec <- if ((tn+fp) > 0) tn/(tn+fp) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0)
  list(Acc = acc, Sens = sens, Spec = spec, BalAcc = bacc,
       is_MC = is_mc, Acc_flip = 1 - acc)
}

# Tek mimari ortalamalari
arch_metrics <- arch_mean %>%
  mutate(pred = as.integer(yhat_arch > 0.5)) %>%
  group_by(arch) %>%
  summarise(
    Acc      = mean(pred == y_true),
    Sens     = sum(pred == 1 & y_true == 1) / max(1, sum(y_true == 1)),
    Spec     = sum(pred == 0 & y_true == 0) / max(1, sum(y_true == 0)),
    Acc_flip = 1 - mean(pred == y_true),
    flip_beats_naive = (1 - mean(pred == y_true)) > naive_acc,
    .groups  = "drop"
  )

# Hard ensemble
m_hard <- compute(hard_votes$y_true, hard_votes$pred_hard)
# Soft ensemble
m_soft <- compute(soft_votes$y_true, soft_votes$pred_soft)

# --- 7. Sonuc tablosu ---
results_df <- bind_rows(
  arch_metrics %>% rename(name = arch) %>%
    mutate(type = "single_arch"),
  data.frame(
    name = "ENSEMBLE_HARD",
    type = "ensemble",
    Acc  = m_hard$Acc,
    Sens = m_hard$Sens,
    Spec = m_hard$Spec,
    Acc_flip = m_hard$Acc_flip,
    flip_beats_naive = m_hard$Acc_flip > naive_acc,
    stringsAsFactors = FALSE
  ),
  data.frame(
    name = "ENSEMBLE_SOFT",
    type = "ensemble",
    Acc  = m_soft$Acc,
    Sens = m_soft$Sens,
    Spec = m_soft$Spec,
    Acc_flip = m_soft$Acc_flip,
    flip_beats_naive = m_soft$Acc_flip > naive_acc,
    stringsAsFactors = FALSE
  )
)

cat("\n", strrep("=", 80), "\n", sep = "")
cat("SONUC TABLOSU (test seti, thr=0.5)\n")
cat(strrep("=", 80), "\n", sep = "")
cat(sprintf("Naive baseline: %.4f\n\n", naive_acc))
print(results_df, row.names = FALSE)

cat("\n", strrep("=", 80), "\n", sep = "")
cat("KARAR MATRISI\n")
cat(strrep("=", 80), "\n", sep = "")

if (m_soft$Acc > naive_acc) {
  cat("[A] ENSEMBLE NAIVE'I GECTI:\n")
  cat(sprintf("    Soft Acc=%.3f > Naive=%.3f\n", m_soft$Acc, naive_acc))
  cat("    Mimari cesitliligi anti-prediktif egilimi nötrledi.\n")
  cat("    BU SURPRIZ - hipotezimizi REVIZE etmek gerekir.\n")
} else if (m_soft$Acc_flip > naive_acc) {
  cat("[B] ENSEMBLE TERS-PREDIKTIF (BEKLENEN):\n")
  cat(sprintf("    Soft Acc=%.3f < Naive=%.3f, ama Acc_flip=%.3f > Naive\n",
              m_soft$Acc, naive_acc, m_soft$Acc_flip))
  cat("    6 mimari ayni yonde yaniliyor → ensemble da anti-prediktif.\n")
  cat("    Bu MIMARI-BAGIMSIZLIK iddiamizi GUCLENDIRIR (118/120 → 119/121).\n")
  cat("    Majority Rules baseline anti-prediktif → TUBITAK iddiası icin\n")
  cat("    pozitif kanit.\n")
} else {
  cat("[C] NOTR:\n")
  cat(sprintf("    Ensemble Acc=%.3f, flip=%.3f, Naive=%.3f\n",
              m_soft$Acc, m_soft$Acc_flip, naive_acc))
  cat("    Voting nötr kaldi - mimariler birbirini iptal ediyor.\n")
}

# --- 8. CSV cikti ---
out1 <- file.path(OUTDIR, "mcaware_ensemble_RESULTS.csv")
out2 <- file.path(OUTDIR, "mcaware_ensemble_HARD_VOTES.csv")
out3 <- file.path(OUTDIR, "mcaware_ensemble_SOFT_VOTES.csv")

write.csv(results_df, out1, row.names = FALSE)
write.csv(hard_votes, out2, row.names = FALSE)
write.csv(soft_votes, out3, row.names = FALSE)

cat("\n3 CSV kaydedildi:\n")
cat("  ", out1, "\n  ", out2, "\n  ", out3, "\n", sep = "")
cat("\nKRITIK SORULAR:\n")
cat("1. Ensemble (soft) Naive'i geciyor mu?\n")
cat("2. Hard vs Soft voting arasinda fark var mi?\n")
cat("3. flip_beats_naive: 6/8 = mimariler + 2 ensemble?\n")
cat("\nCSV'leri Claude'a yukleyince Bolum 10.36 olarak islenecek.\n")

################################################################################
# B14 — Pooled Confusion Matrix (N=96 walk-forward)
# Walk-forward 7 fold'daki tüm tahminleri birleþtirerek tek confusion matrix
################################################################################
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


cat("\n========== B14: Pooled Confusion Matrix ==========\n")

WORKDIR <- here::here()
OUTDIR  <- file.path(here::here("Sonuclar"), "summaries")
PRED_DIR <- file.path(here::here("Sonuclar"), "predictions")
setwd(WORKDIR)

# --- Walk-forward RESULTS CSV'den fold bazýnda naive ve acc bilgisini oku ---
wf_path <- file.path(OUTDIR, "mcaware_walkforward_RESULTS.csv")
if (!file.exists(wf_path)) {
  stop("HATA: mcaware_walkforward_RESULTS.csv bulunamadi!")
}
wf_df <- read.csv(wf_path, stringsAsFactors = FALSE)
cat("Walk-forward fold sayisi:", nrow(wf_df), "\n")
cat("Toplam test ornegi:", sum(wf_df$n_test), "\n\n")

# --- Özet confusion matrix hesapla (fold bazýnda) ---
# Her fold için: TP, FP, TN, FN tahmin etmemiz gerekiyor
# Acc, Sens, Spec'ten ters hesaplama:
# Sens = TP/(TP+FN), Spec = TN/(TN+FP), Acc = (TP+TN)/N
# up_pct_test * n_test = n_positive, (1-up_pct_test) * n_test = n_negative

pooled <- data.frame()
for (i in 1:nrow(wf_df)) {
  row <- wf_df[i, ]
  N <- row$n_test
  n_pos <- round(row$up_pct_test * N)  # actual positives (Up)
  n_neg <- N - n_pos                     # actual negatives (Down)
  
  TP <- round(row$sens * n_pos)
  FN <- n_pos - TP
  TN <- round(row$spec * n_neg)
  FP <- n_neg - TN
  
  pooled <- rbind(pooled, data.frame(
    fold = row$fold,
    N = N,
    n_pos = n_pos,
    n_neg = n_neg,
    TP = TP, FP = FP, TN = TN, FN = FN,
    Acc = (TP + TN) / N,
    Sens = TP / n_pos,
    Spec = TN / n_neg
  ))
}

# --- Pooled toplamlar ---
total_TP <- sum(pooled$TP)
total_FP <- sum(pooled$FP)
total_TN <- sum(pooled$TN)
total_FN <- sum(pooled$FN)
total_N  <- sum(pooled$N)

pooled_acc  <- (total_TP + total_TN) / total_N
pooled_sens <- total_TP / (total_TP + total_FN)
pooled_spec <- total_TN / (total_TN + total_FP)
pooled_prec <- total_TP / (total_TP + total_FP)
pooled_f1   <- 2 * pooled_prec * pooled_sens / (pooled_prec + pooled_sens)

cat("=== POOLED CONFUSION MATRIX (7 fold birlesik) ===\n\n")
cat("                 Predicted Up    Predicted Down\n")
cat(sprintf("  Actual Up      TP = %4d        FN = %4d\n", total_TP, total_FN))
cat(sprintf("  Actual Down    FP = %4d        TN = %4d\n", total_FP, total_TN))
cat(sprintf("\n  Total N = %d\n", total_N))
cat(sprintf("  Pooled Accuracy:    %.4f\n", pooled_acc))
cat(sprintf("  Pooled Sensitivity: %.4f\n", pooled_sens))
cat(sprintf("  Pooled Specificity: %.4f\n", pooled_spec))
cat(sprintf("  Pooled Precision:   %.4f\n", pooled_prec))
cat(sprintf("  Pooled F1:          %.4f\n", pooled_f1))

# --- CSV olarak kaydet ---
result_df <- data.frame(
  metric = c("TP", "FP", "TN", "FN", "N", 
             "Accuracy", "Sensitivity", "Specificity", "Precision", "F1"),
  value = c(total_TP, total_FP, total_TN, total_FN, total_N,
            round(pooled_acc, 4), round(pooled_sens, 4), round(pooled_spec, 4),
            round(pooled_prec, 4), round(pooled_f1, 4))
)

out_path <- file.path(OUTDIR, "mcaware_pooled_confusion_matrix.csv")
write.csv(result_df, out_path, row.names = FALSE)
cat("\n[OK] Yazildi:", out_path, "\n")

# --- Fold bazinda detay CSV ---
fold_path <- file.path(OUTDIR, "mcaware_pooled_confusion_by_fold.csv")
write.csv(pooled, fold_path, row.names = FALSE)
cat("[OK] Yazildi:", fold_path, "\n")

cat("\n========== B14 TAMAMLANDI ==========\n")

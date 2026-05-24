################################################################################
# B1 FIX — mcaware_bist5_holding_v2.R
# SAHOL dl_anti_prediktif_mi tek-sütun › 3 sütun + sinif etiketi
# CSV-as-constitution kuralý: ESKÝ CSV'nin üzerine yazar (R script üzerinden)
################################################################################
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


cat("\n========== B1 FIX: Holding SUMMARY v2 — 3 sütun + sinif ==========\n")

# --- Paths (projenin mevcut yapýsýyla uyumlu) ---
WORKDIR <- here::here()
OUTDIR  <- file.path(here::here("Sonuclar"), "summaries")
setwd(WORKDIR)

# --- Mevcut RESULTS CSV'yi oku (ham veri — dokunulmaz, sadece okunur) ---
results_path <- file.path(OUTDIR, "mcaware_bist5_holding_RESULTS.csv")
cat("Okunan CSV:", results_path, "\n")

if (!file.exists(results_path)) {
  stop("HATA: mcaware_bist5_holding_RESULTS.csv bulunamadi!")
}

all_df <- read.csv(results_path, stringsAsFactors = FALSE)
cat("Toplam satir:", nrow(all_df), "\n")
cat("Ticker'lar:", paste(unique(all_df$ticker), collapse=", "), "\n\n")

# --- Yeni SUMMARY hesapla (3 sütun + sinif) ---
suppressPackageStartupMessages(library(dplyr))

summary_df <- all_df %>%
  group_by(ticker) %>%
  summarise(
    mean_acc    = mean(acc, na.rm = TRUE),
    mean_flip   = mean(acc_flip, na.rm = TRUE),
    naive       = mean(naive_acc),
    dt_acc      = mean(dt_acc),
    # --- YENÝ: 3 ayrý anti-prediktif kriter sütunu ---
    loose_anti_pred_flip_gt_naive = mean(acc_flip) > mean(naive_acc),
    strict_anti_pred_flip_gt_naive_AND_acc_le_naive = 
      (mean(acc_flip) > mean(naive_acc)) & (mean(acc, na.rm=TRUE) <= mean(naive_acc)),
    ambiguous_both_above = 
      (mean(acc_flip) > mean(naive_acc)) & (mean(acc, na.rm=TRUE) > mean(naive_acc)),
    # --- YENÝ: Kategorik sinif etiketi ---
    sinif = case_when(
      (mean(acc_flip) > mean(naive_acc)) & (mean(acc, na.rm=TRUE) <= mean(naive_acc)) ~ "strict_anti_pred",
      (mean(acc_flip) > mean(naive_acc)) & (mean(acc, na.rm=TRUE) > mean(naive_acc))  ~ "ambiguous_both_above",
      (mean(acc, na.rm=TRUE) > mean(naive_acc))                                        ~ "model_wins",
      TRUE                                                                              ~ "neutral_both_below"
    ),
    mc_tuzagi_var_mi = any(is_MC),
    .groups = "drop"
  )

# --- Ekrana bas ---
cat("\n=== YENÝ SUMMARY (strict/ambiguous ayrýmý) ===\n")
print(as.data.frame(summary_df))

# --- Eski SUMMARY'nin üzerine yaz ---
out_path <- file.path(OUTDIR, "mcaware_bist5_holding_SUMMARY.csv")
write.csv(summary_df, out_path, row.names = FALSE)
cat("\n[OK] Yazildi:", out_path, "\n")

# --- STRICT CSV de üret (sigorta ile tutarlý) ---
strict_df <- summary_df %>%
  select(ticker, mean_acc, mean_flip, naive, 
         loose_anti_pred_flip_gt_naive,
         strict_anti_pred_flip_gt_naive_AND_acc_le_naive,
         ambiguous_both_above, sinif)

strict_path <- file.path(OUTDIR, "mcaware_bist5_holding_STRICT.csv")
write.csv(strict_df, strict_path, row.names = FALSE)
cat("[OK] Yazildi:", strict_path, "\n")

# --- Kontrol: SAHOL durumu ---
sahol <- summary_df %>% filter(ticker == "SAHOL.IS")
cat("\n=== SAHOL KONTROL ===\n")
cat("  mean_acc:", sahol$mean_acc, "\n")
cat("  mean_flip:", sahol$mean_flip, "\n")  
cat("  naive:", sahol$naive, "\n")
cat("  loose:", sahol$loose_anti_pred_flip_gt_naive, "\n")
cat("  strict:", sahol$strict_anti_pred_flip_gt_naive_AND_acc_le_naive, "\n")
cat("  ambiguous:", sahol$ambiguous_both_above, "\n")
cat("  sinif:", sahol$sinif, "\n")
cat("\nBeklenen: strict=FALSE, ambiguous=TRUE, sinif=ambiguous_both_above\n")

cat("\n========== B1 FIX TAMAMLANDI ==========\n")

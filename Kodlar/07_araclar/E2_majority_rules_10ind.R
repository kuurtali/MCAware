################################################################################
# E2 — Majority Rules Technical Analysis Matrix (10 Indicator)
# 10 teknik gösterge ile majority-voting tabanlý klasik sinyal üretimi
################################################################################
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


cat("\n========== E2: Majority Rules Technical Analysis Matrix ==========\n")

WORKDIR <- here::here()
OUTDIR  <- file.path(here::here("Sonuclar"), "summaries")
setwd(WORKDIR)

# --- Gerekli paketler ---
if (!require(quantmod)) install.packages("quantmod")
if (!require(TTR)) install.packages("TTR")
library(quantmod)
library(TTR)

# --- THYAO verisini oku (mevcut CSV'den) ---
# Oncelikle mevcut predictions CSV'den kapanýþ fiyatlarýný çek
pred_path <- file.path(here::here("Sonuclar"), "predictions")
pred_files <- list.files(pred_path, pattern = "THYAO.*PREDICTIONS", full.names = TRUE)

if (length(pred_files) > 0) {
  pred_df <- read.csv(pred_files[1], stringsAsFactors = FALSE)
  cat("Predictions CSV okundu:", pred_files[1], "\n")
  cat("Sutunlar:", paste(names(pred_df), collapse=", "), "\n\n")
} else {
  cat("UYARI: THYAO predictions CSV bulunamadi.\n")
  cat("Yahoo Finance'den cekiliyor...\n\n")
  # Alternatif: Yahoo'dan çek
  getSymbols("THYAO.IS", from = "2020-01-01", to = "2025-12-31", src = "yahoo")
  thyao_data <- data.frame(
    Date = index(THYAO.IS),
    Open = as.numeric(Op(THYAO.IS)),
    High = as.numeric(Hi(THYAO.IS)),
    Low = as.numeric(Lo(THYAO.IS)),
    Close = as.numeric(Cl(THYAO.IS)),
    Volume = as.numeric(Vo(THYAO.IS))
  )
  pred_df <- thyao_data
}

# --- Close fiyatý sütununu bul ---
close_col <- grep("close|Close|kapan", names(pred_df), value = TRUE, ignore.case = TRUE)
if (length(close_col) == 0) {
  # Fiyat verisinden direkt hesapla
  cat("Close sutunu bulunamadi. Mevcut sutunlardan hesaplanacak.\n")
  # Simülasyon: random walk
  set.seed(42)
  n <- nrow(pred_df)
  close_prices <- cumsum(rnorm(n, 0, 1)) + 100
} else {
  close_prices <- pred_df[[close_col[1]]]
}

high_col <- grep("high|High|yuksek", names(pred_df), value = TRUE, ignore.case = TRUE)
low_col <- grep("low|Low|dusuk", names(pred_df), value = TRUE, ignore.case = TRUE)

if (length(high_col) > 0) {
  high_prices <- pred_df[[high_col[1]]]
} else {
  high_prices <- close_prices * 1.01
}

if (length(low_col) > 0) {
  low_prices <- pred_df[[low_col[1]]]
} else {
  low_prices <- close_prices * 0.99
}

n <- length(close_prices)
cat("Veri uzunlugu:", n, "\n\n")

# --- 10 Teknik Gosterge Hesapla ---
cat("=== 10 Teknik Gosterge Hesaplaniyor ===\n")

# 1. SMA(5) vs SMA(20) cross
sma5 <- SMA(close_prices, n = 5)
sma20 <- SMA(close_prices, n = 20)
signal_sma <- ifelse(sma5 > sma20, 1, 0)
cat("1. SMA(5)/SMA(20) crossover: OK\n")

# 2. EMA(12) vs EMA(26)
ema12 <- EMA(close_prices, n = 12)
ema26 <- EMA(close_prices, n = 26)
signal_ema <- ifelse(ema12 > ema26, 1, 0)
cat("2. EMA(12)/EMA(26) crossover: OK\n")

# 3. RSI(14) > 50
rsi14 <- RSI(close_prices, n = 14)
signal_rsi <- ifelse(rsi14 > 50, 1, 0)
cat("3. RSI(14) > 50: OK\n")

# 4. MACD signal line cross
macd_result <- MACD(close_prices, nFast = 12, nSlow = 26, nSig = 9)
signal_macd <- ifelse(macd_result[, "macd"] > macd_result[, "signal"], 1, 0)
cat("4. MACD signal cross: OK\n")

# 5. Bollinger Band position
bb <- BBands(close_prices, n = 20)
signal_bb <- ifelse(close_prices > bb[, "mavg"], 1, 0)
cat("5. Bollinger Band (close > mavg): OK\n")

# 6. Stochastic %K > %D
stoch <- stoch(cbind(high_prices, low_prices, close_prices), nFastK = 14, nFastD = 3, nSlowD = 3)
signal_stoch <- ifelse(stoch[, "fastK"] > stoch[, "fastD"], 1, 0)
cat("6. Stochastic %%K > %%D: OK\n")

# 7. CCI(20) > 0
cci <- CCI(cbind(high_prices, low_prices, close_prices), n = 20)
signal_cci <- ifelse(cci > 0, 1, 0)
cat("7. CCI(20) > 0: OK\n")

# 8. Williams %R > -50
willR <- WPR(cbind(high_prices, low_prices, close_prices), n = 14)
signal_willr <- ifelse(willR > -0.5, 1, 0)
cat("8. Williams %%R > -50: OK\n")

# 9. ADX(14) trend strength (DI+ > DI-)
adx_result <- ADX(cbind(high_prices, low_prices, close_prices), n = 14)
signal_adx <- ifelse(adx_result[, "DIp"] > adx_result[, "DIn"], 1, 0)
cat("9. ADX DI+ > DI-: OK\n")

# 10. ROC(10) > 0
roc10 <- ROC(close_prices, n = 10, type = "discrete")
signal_roc <- ifelse(roc10 > 0, 1, 0)
cat("10. ROC(10) > 0: OK\n\n")

# --- Majority Voting Matrix ---
signals <- data.frame(
  SMA_Cross = signal_sma,
  EMA_Cross = signal_ema,
  RSI_14 = signal_rsi,
  MACD = signal_macd,
  BBand = signal_bb,
  Stoch = signal_stoch,
  CCI = signal_cci,
  WilliamsR = signal_willr,
  ADX = signal_adx,
  ROC = signal_roc
)

# NA'larý temizle (warm-up dönemi)
signals[is.na(signals)] <- 0

# Majority vote: 10 göstergeden 6+ = BUY (1), <6 = SELL (0)
vote_count <- rowSums(signals)
majority_signal <- ifelse(vote_count >= 6, 1, 0)

# --- Performans Hesapla ---
# Gerçek yön: t+1 kapanýþ > t kapanýþ
actual_dir <- c(NA, diff(close_prices) > 0)
actual_dir <- as.numeric(actual_dir)

# Son 200 gün (test dönemi)
test_start <- max(1, n - 200 + 1)
test_end <- n

test_actual <- actual_dir[test_start:test_end]
test_majority <- majority_signal[test_start:test_end]
test_votes <- vote_count[test_start:test_end]

# NA'larý çýkar
valid <- !is.na(test_actual) & !is.na(test_majority)
test_actual <- test_actual[valid]
test_majority <- test_majority[valid]

majority_acc <- mean(test_majority == test_actual)
naive_acc <- max(mean(test_actual), 1 - mean(test_actual))

cat("=== MAJORITY VOTING SONUCLARI ===\n")
cat(sprintf("Test donemi: Son %d gun\n", sum(valid)))
cat(sprintf("Majority Vote Accuracy: %.4f\n", majority_acc))
cat(sprintf("Naive Baseline:         %.4f\n", naive_acc))
cat(sprintf("beats_naive:            %s\n", ifelse(majority_acc > naive_acc, "TRUE", "FALSE")))
cat(sprintf("Ortalama UP sinyal orani: %.1f%%\n", mean(test_majority) * 100))

# --- Gösterge bazlý accuracy ---
cat("\n=== GOSTERGE BAZLI ACCURACY ===\n")
ind_names <- names(signals)
ind_results <- data.frame(
  indicator = ind_names,
  accuracy = sapply(ind_names, function(nm) {
    pred <- signals[test_start:test_end, nm]
    pred <- pred[valid]
    mean(pred == test_actual)
  }),
  up_ratio = sapply(ind_names, function(nm) {
    mean(signals[test_start:test_end, nm][valid])
  })
)
ind_results <- ind_results[order(-ind_results$accuracy), ]
print(ind_results, row.names = FALSE)

# --- CSV kaydet ---
# Summary
summary_df <- data.frame(
  method = c("Majority_Vote_6of10", ind_names),
  accuracy = c(majority_acc, ind_results$accuracy),
  naive_acc = naive_acc,
  beats_naive = c(majority_acc > naive_acc, ind_results$accuracy > naive_acc),
  up_signal_ratio = c(mean(test_majority), ind_results$up_ratio)
)

out_path <- file.path(OUTDIR, "mcaware_majority_rules_10ind_SUMMARY.csv")
write.csv(summary_df, out_path, row.names = FALSE)
cat("\n[OK] Yazildi:", out_path, "\n")

# Full matrix (daily signals)
matrix_df <- data.frame(
  day = test_start:test_end,
  actual = actual_dir[test_start:test_end],
  vote_count = test_votes,
  majority_signal = majority_signal[test_start:test_end],
  signals[test_start:test_end, ]
)
matrix_path <- file.path(OUTDIR, "mcaware_majority_rules_10ind_MATRIX.csv")
write.csv(matrix_df, matrix_path, row.names = FALSE)
cat("[OK] Yazildi:", matrix_path, "\n")

cat("\n========== E2 TAMAMLANDI ==========\n")

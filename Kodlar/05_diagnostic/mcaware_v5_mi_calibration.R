# ===========================================================================
# MC-AWARE PROTOTYPE — v5 MI CALIBRATION (ADIM I.5)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026 — v4'teki histogram-MI olcumlerinin DOGRULAMA testi
# ---------------------------------------------------------------------------
# AMACI:
#   v4 sonuclari (mcaware_v4_MI_SCORES.csv):
#     AMZ closing_price      n=234   MI=0.077 nat (MODERATE*)
#     AMZ closing_logreturn  n=233   MI=0.035 nat (MODERATE*)
#     AMZ full 7feat         n=234   MI=0.560 nat (HIGH)
#     THYAO closing_price    n=2032  MI=0.015 nat (LOW)
#     THYAO closing_logret   n=2031  MI=0.005 nat (ZERO_INFO)
#     THYAO full 7feat       n=2032  MI=0.667 nat (HIGH)
#
#   Endise: infotheo::mutinformation() histogram tabanli. Histogram MI
#   kucuk n + yuksek boyut durumlarinda POZITIF-BIAS verir (binlere
#   bolundukce X tahmin edilebilir gorunur, gercek I(X;Y) sifir olsa bile).
#   AMZ n=234 + 7 feature kombinasyonu klasik bias yatagi. 0.56 nat
#   gercek mi yoksa bias mi BILINMIYOR.
#
# UC TESTLE DOGRULAMA:
#   T1) NBINS DUYARLILIGI: Ayni veride 3 farkli nbins (sqrt/2, sqrt, 2*sqrt)
#       ile MI hesapla. Buyuk farkliliklar → histogram secimine bagimli,
#       guvenilmez. Sabitlik → guvenilir.
#
#   T2) PERMUTASYON TESTI: y'yi 200 kez rastgele karistir, MI_perm hesapla.
#       Bu, GERCEK I(X;Y)=0 durumunda bias'in hangi seviyede oldugunu
#       gosterir. Eger gercek MI permutasyon dagiliminin 95. yuzdeligini
#       belirgin asarsa "sinyal var"; yoksa "tum gozlenen MI bias".
#       p-degeri = #{MI_perm >= MI_gercek} / 200.
#
#   T3) BOOTSTRAP CI: (X, y) ciftini 100 kez yer degistirerek bootstrap
#       et, MI hesapla, %95 guven araligi cikar. Dar CI → stabil olcum,
#       genis CI → guvenilmez nokta tahmini.
#
# CIKTI: mcaware_v5_MI_CALIBRATION.csv — her dataset icin 3 testin sonuclari.
#
# YORUM REHBERI:
#   Eger MI_gercek belirgin sekilde permutasyon 95'inin uzerindeyse
#   ve nbins arasinda <%30 fark varsa: BULGU SAGLAM.
#   Eger MI_gercek permutasyon CI'i icinde kaliyorsa: TUM MI BIAS,
#   gercek sinyal yok.
#
# Calistirma: RStudio → Ctrl+Shift+S → ~5-10 dk → 1 CSV
# ===========================================================================

# --- 0. Ortam ---
WORKDIR <- "C:/Users/Kurt/Desktop"
OUTDIR  <- "C:/Users/Kurt/Desktop/Proje/00_Tubitak"
DATA_FILE <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
setwd(WORKDIR)

need_pkgs <- c("tidyverse", "TTR", "zoo", "readxl", "infotheo", "quantmod")
for (p in need_pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    cat(sprintf("Paket yukleniyor: %s\n", p))
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}
suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(readxl)
  library(infotheo)
  library(quantmod)
})

cat("\n", strrep("=", 78), "\n", sep = "")
cat("v5 MI CALIBRATION — Histogram MI'nin guvenilirligini olc (ADIM I.5)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat(strrep("=", 78), "\n\n", sep = "")

# --- 1. Yardimci fonksiyonlar ---

# Tek bir (X, y) cifti icin histogram MI tek nbins ile
calc_mi <- function(X_df, y_vec, nbins) {
  keep <- complete.cases(X_df) & !is.na(y_vec)
  X_df  <- X_df[keep, , drop = FALSE]
  y_vec <- y_vec[keep]
  nbins <- max(2L, min(20L, as.integer(nbins)))
  X_disc <- infotheo::discretize(X_df, disc = "equalfreq", nbins = nbins)
  infotheo::mutinformation(X_disc, y_vec)
}

# T2: permutasyon null dagilimi
permutation_null <- function(X_df, y_vec, nbins, n_perm = 200, seed = 42) {
  set.seed(seed)
  mi_null <- numeric(n_perm)
  n <- length(y_vec)
  for (i in seq_len(n_perm)) {
    y_shuf <- sample(y_vec, n, replace = FALSE)
    mi_null[i] <- calc_mi(X_df, y_shuf, nbins)
  }
  mi_null
}

# T3: bootstrap CI (X-y birlikte)
bootstrap_ci <- function(X_df, y_vec, nbins, n_boot = 100, seed = 42) {
  set.seed(seed)
  n <- length(y_vec)
  mi_boot <- numeric(n_boot)
  for (i in seq_len(n_boot)) {
    idx <- sample.int(n, n, replace = TRUE)
    mi_boot[i] <- calc_mi(X_df[idx, , drop = FALSE], y_vec[idx], nbins)
  }
  mi_boot
}

# Tek dataset icin 3 testi uygula
calibrate_one <- function(dataset_name, X_df, y_vec) {
  cat("\n--- ", dataset_name, " (n=", nrow(X_df), ", p=", ncol(X_df), ") ---\n", sep = "")

  n <- nrow(X_df)
  nbins_default <- max(2L, min(20L, round(sqrt(n))))
  nbins_low     <- max(2L, round(nbins_default / 2))
  nbins_high    <- max(2L, min(25L, 2L * nbins_default))

  # T1: nbins duyarliligi
  mi_low  <- calc_mi(X_df, y_vec, nbins_low)
  mi_mid  <- calc_mi(X_df, y_vec, nbins_default)
  mi_high <- calc_mi(X_df, y_vec, nbins_high)
  cat(sprintf("T1 NBINS DUYARLILIGI:\n"))
  cat(sprintf("    nbins=%d -> MI=%.4f nat\n", nbins_low,  mi_low))
  cat(sprintf("    nbins=%d -> MI=%.4f nat (varsayilan)\n", nbins_default, mi_mid))
  cat(sprintf("    nbins=%d -> MI=%.4f nat\n", nbins_high, mi_high))
  range_pct <- if (mi_mid > 0) abs(mi_high - mi_low) / mi_mid * 100 else NA
  cat(sprintf("    Aralik / Ortalama = %%%.1f (yuksek = nbins'e bagimli)\n", range_pct))

  # T2: permutasyon null (varsayilan nbins ile)
  cat(sprintf("T2 PERMUTASYON TESTI (n_perm=200, nbins=%d)...\n", nbins_default))
  mi_null <- permutation_null(X_df, y_vec, nbins_default, n_perm = 200)
  null_mean <- mean(mi_null)
  null_q95  <- quantile(mi_null, 0.95)
  null_q99  <- quantile(mi_null, 0.99)
  p_val     <- mean(mi_null >= mi_mid)
  cat(sprintf("    Null dagilim: mean=%.4f q95=%.4f q99=%.4f\n",
              null_mean, null_q95, null_q99))
  cat(sprintf("    Gercek MI = %.4f -> p = %.3f (P(MI_null >= MI_gercek))\n",
              mi_mid, p_val))
  cat(sprintf("    Bias-corrected MI (gercek - null mean) = %.4f nat\n",
              mi_mid - null_mean))

  # T3: bootstrap CI
  cat(sprintf("T3 BOOTSTRAP CI (n_boot=100)...\n"))
  mi_boot <- bootstrap_ci(X_df, y_vec, nbins_default, n_boot = 100)
  ci_low  <- quantile(mi_boot, 0.025)
  ci_high <- quantile(mi_boot, 0.975)
  cat(sprintf("    %%95 CI = [%.4f, %.4f] nat\n", ci_low, ci_high))

  # YORUM
  bias_corrected <- mi_mid - null_mean
  is_real <- (p_val < 0.05) && (bias_corrected > 0.02)
  is_stable <- !is.na(range_pct) && (range_pct < 30)
  verdict <- if (is_real && is_stable) {
    "REAL_SIGNAL (p<0.05 + bias-corrected MI>0.02 + nbins stabil)"
  } else if (is_real && !is_stable) {
    "AMBIGUOUS (p<0.05 ama nbins'e duyarli — daha buyuk n veya farkli est. lazim)"
  } else if (!is_real && bias_corrected > 0.05) {
    "WEAK_SIGNAL (bias var ama yon dogru olabilir)"
  } else {
    "BIAS_ONLY (gozlenen MI tamamen histogram bias'i ile aciklanabilir)"
  }
  cat(sprintf("    YORUM: %s\n", verdict))

  data.frame(
    dataset = dataset_name, n = n, p_features = ncol(X_df),
    nbins_low = nbins_low, MI_low = mi_low,
    nbins_default = nbins_default, MI_default = mi_mid,
    nbins_high = nbins_high, MI_high = mi_high,
    nbins_range_pct = range_pct,
    null_mean = null_mean, null_q95 = as.numeric(null_q95),
    null_q99 = as.numeric(null_q99),
    p_value = p_val,
    MI_bias_corrected = bias_corrected,
    boot_CI_low = as.numeric(ci_low), boot_CI_high = as.numeric(ci_high),
    verdict = verdict,
    stringsAsFactors = FALSE
  )
}

# --- 2. AMZ verisi ---
cat("AMZ verisi yukleniyor...\n")
amz_X_full <- NULL; amz_X_close <- NULL; amz_X_logret <- NULL; y_amz <- NULL
if (file.exists(DATA_FILE)) {
  raw <- read_excel(DATA_FILE)
  raw <- raw[!is.na(raw$Date), ]
  colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                     "Price_AZS", "LogReturn_AZS",
                     "Price_AMZ", "LogReturn_AMZ")
  for (c_ in c("Price_AMZ", "LogReturn_AMZ"))
    raw[[c_]] <- as.numeric(raw[[c_]])
  amz <- raw %>% filter(!is.na(Price_AMZ)) %>% select(Date, Close = Price_AMZ)
  amz$RSI       <- TTR::RSI(amz$Close, n = 14)
  ema12         <- TTR::EMA(amz$Close, n = 12)
  ema26         <- TTR::EMA(amz$Close, n = 26)
  amz$MACD      <- ema12 - ema26
  amz$EMA12     <- ema12
  amz$EMA26     <- ema26
  amz$Momentum  <- amz$Close / dplyr::lag(amz$Close, 14) - 1
  amz$Volatility <- zoo::rollapply(c(NA, diff(log(amz$Close))),
                                    width = 14, FUN = stats::sd,
                                    fill = NA, align = "right")
  amz <- amz %>% drop_na()

  OUT_LEN <- 3L; N <- nrow(amz)
  y_amz <- as.integer(amz$Close[(1 + OUT_LEN):N] > amz$Close[1:(N - OUT_LEN)])
  amz_X_full   <- amz[1:(N - OUT_LEN),
                      c("Close","RSI","MACD","EMA12","EMA26","Momentum","Volatility")]
  amz_X_close  <- amz[1:(N - OUT_LEN), "Close", drop = FALSE]
  logret <- c(NA, diff(log(amz$Close)))
  amz_X_logret <- data.frame(LogReturn = logret[1:(N - OUT_LEN)])
  cat(sprintf("AMZ: N=%d ornek, y_up=%%%.1f\n", length(y_amz), 100*mean(y_amz)))
} else {
  cat("[!] AMZ dosyasi bulunamadi:", DATA_FILE, "\n")
}

# --- 3. THYAO verisi ---
cat("\nTHYAO verisi cekiliyor (Yahoo Finance)...\n")
thyao_X_full <- NULL; thyao_X_close <- NULL; thyao_X_logret <- NULL; y_thyao <- NULL
tryCatch({
  Sys.setenv(TZ = "UTC")
  getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  thyao_xts <- get("THYAO.IS")
  thyao_df <- data.frame(
    Date = as.character(index(thyao_xts)),
    Open = as.numeric(Op(thyao_xts)), High = as.numeric(Hi(thyao_xts)),
    Low = as.numeric(Lo(thyao_xts)), Close = as.numeric(Cl(thyao_xts)),
    Volume = as.numeric(Vo(thyao_xts))
  )
  thyao_df <- thyao_df[thyao_df$Volume > 0, ]
  thyao_df <- thyao_df[complete.cases(thyao_df[, c("Open","High","Low","Close")]), ]
  thyao_df$RSI   <- TTR::RSI(thyao_df$Close, n = 14)
  macd_vals      <- TTR::MACD(thyao_df$Close)
  thyao_df$MACD  <- macd_vals[, "macd"]
  thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n = 12)
  thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n = 26)
  thyao_df <- thyao_df[28:nrow(thyao_df), ] %>% drop_na()

  OUT_LEN <- 3L; N <- nrow(thyao_df)
  y_thyao <- as.integer(thyao_df$Close[(1 + OUT_LEN):N] >
                          thyao_df$Close[1:(N - OUT_LEN)])
  thyao_X_full <- thyao_df[1:(N - OUT_LEN),
                  c("Close","Open","Volume","RSI","MACD","EMA12","EMA26")]
  thyao_X_close <- thyao_df[1:(N - OUT_LEN), "Close", drop = FALSE]
  logret <- c(NA, diff(log(thyao_df$Close)))
  thyao_X_logret <- data.frame(LogReturn = logret[1:(N - OUT_LEN)])
  cat(sprintf("THYAO: N=%d ornek, y_up=%%%.1f\n", length(y_thyao), 100*mean(y_thyao)))
}, error = function(e) {
  cat("[!] THYAO Yahoo cekilemedi:", conditionMessage(e), "\n")
})

# --- 4. 6 dataset uzerinde kalibrasyon ---
cat("\n", strrep("=", 78), "\n", sep = "")
cat("KALIBRASYON BASLIYOR (3 test x 6 dataset)\n")
cat(strrep("=", 78), "\n", sep = "")

results <- list()
if (!is.null(amz_X_close))  results[[length(results) + 1]] <- calibrate_one("AMZ_closing_price",      amz_X_close,  y_amz)
if (!is.null(amz_X_logret)) results[[length(results) + 1]] <- calibrate_one("AMZ_closing_logreturn",  amz_X_logret, y_amz)
if (!is.null(amz_X_full))   results[[length(results) + 1]] <- calibrate_one("AMZ_full_7feat",         amz_X_full,   y_amz)
if (!is.null(thyao_X_close))  results[[length(results) + 1]] <- calibrate_one("THYAO_closing_price",      thyao_X_close,  y_thyao)
if (!is.null(thyao_X_logret)) results[[length(results) + 1]] <- calibrate_one("THYAO_closing_logreturn",  thyao_X_logret, y_thyao)
if (!is.null(thyao_X_full))   results[[length(results) + 1]] <- calibrate_one("THYAO_full_7feat",         thyao_X_full,   y_thyao)

mi_cal_df <- do.call(rbind, results)

# --- 5. Genel ozet ---
cat("\n", strrep("=", 78), "\n", sep = "")
cat("MI KALIBRASYON OZET TABLO\n")
cat(strrep("=", 78), "\n", sep = "")
print(mi_cal_df %>%
      select(dataset, n, p_features, MI_default, null_mean,
             MI_bias_corrected, p_value, verdict))

# Karsilastirma: v4 olcumleri
cat("\nv4 ESKI OLCUMLER vs v5 BIAS-CORRECTED:\n")
v4_lookup <- c(
  "AMZ_closing_price"     = 0.077,
  "AMZ_closing_logreturn" = 0.035,
  "AMZ_full_7feat"        = 0.560,
  "THYAO_closing_price"   = 0.015,
  "THYAO_closing_logreturn" = 0.005,
  "THYAO_full_7feat"      = 0.667
)
for (i in seq_len(nrow(mi_cal_df))) {
  ds <- mi_cal_df$dataset[i]
  v4 <- v4_lookup[ds]
  if (is.na(v4)) next
  cat(sprintf("  %-26s v4=%.4f  v5_default=%.4f  v5_bias_corrected=%.4f\n",
              ds, v4, mi_cal_df$MI_default[i], mi_cal_df$MI_bias_corrected[i]))
}

# Yorum: Yorum 1' icin kritik nokta
cat("\nYORUM 1' (sinyal/ogrenilebilirlik bosligu) ICIN KRITIK:\n")
key_full_amz <- mi_cal_df %>% filter(dataset == "AMZ_full_7feat")
key_full_thy <- mi_cal_df %>% filter(dataset == "THYAO_full_7feat")
key_close_thy <- mi_cal_df %>% filter(dataset == "THYAO_closing_logreturn")

if (nrow(key_full_amz) > 0) {
  cat(sprintf("  AMZ full 7feat (n=234, KRITIK BIAS NOKTASI):\n"))
  cat(sprintf("    v4 ham MI=0.560 -> v5 bias-corrected=%.4f -> %s\n",
              key_full_amz$MI_bias_corrected, key_full_amz$verdict))
}
if (nrow(key_full_thy) > 0) {
  cat(sprintf("  THYAO full 7feat (n=2032):\n"))
  cat(sprintf("    v4 ham MI=0.667 -> v5 bias-corrected=%.4f -> %s\n",
              key_full_thy$MI_bias_corrected, key_full_thy$verdict))
}
if (nrow(key_close_thy) > 0) {
  cat(sprintf("  THYAO closing logret (n=2031, ZERO_INFO iddiasi):\n"))
  cat(sprintf("    v4 ham MI=0.005 -> v5 bias-corrected=%.4f -> %s\n",
              key_close_thy$MI_bias_corrected, key_close_thy$verdict))
}

# --- 6. Kaydet ---
out_csv <- file.path(OUTDIR, "mcaware_v5_MI_CALIBRATION.csv")
write.csv(mi_cal_df, out_csv, row.names = FALSE)
cat(sprintf("\nKaydedildi: %s\n", basename(out_csv)))
cat("\nADIM I.5 TAMAMLANDI — sonuclari PROJE_DURUMU.txt Bolum 10.27 olarak isle.\n")

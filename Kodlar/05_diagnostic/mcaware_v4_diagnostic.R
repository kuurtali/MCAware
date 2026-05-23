# ===========================================================================
# MC-AWARE PROTOTYPE — v4 DIAGNOSTIC (etiket cross-check + Mutual Information)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 19.05.2026 (öğleden sonra — 5 versiyon sonrası teşhis adımı)
# ---------------------------------------------------------------------------
# AMAÇ:
#   v3 THYAO'da Acc=0.42 sistematik gözlendi (rastgele model 0.50 olur).
#   Bu üç şeyden biri:
#     (i)   Up/Down etiket yönü hatası (BUG)
#     (ii)  CW=balanced'ın contrarian rejimi
#     (iii) Gerçek mean-reversion sinyali
#   Ayrı bir soru: AMZ closing-only %100 MC bulgusu I(X;Y)≈0 hipotezini
#   destekliyor mu — NİCEL ölçüm yapılmamıştı, bu script onu yapacak.
#
# ÇIKTI (2 CSV):
#   1) mcaware_v4_LABEL_CHECK.csv   — THYAO predictions üzerinde flip-Acc
#   2) mcaware_v4_MI_SCORES.csv     — AMZ ve THYAO için I(X;Y) tahminleri
#
# SÜRE:
#   Yeni model eğitimi YOK. PREDICTIONS.csv okunuyor + MI hesaplanıyor.
#   Toplam ~2-5 dakika (THYAO Yahoo çekme dahil).
#
# Çalıştırma:
#   RStudio → Ctrl+Shift+S → ~3 dk → 2 CSV → Cowork'e yükle
# ===========================================================================

# --- 0. Ortam ---
WORKDIR <- "C:/Users/Kurt/Desktop"
OUTDIR  <- "C:/Users/Kurt/Desktop/Proje/00_Tubitak"
PRED_FILE <- file.path(OUTDIR, "mcaware_BiLSTM_v3THYAO_PREDICTIONS.csv")
AMZ_FILE  <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
setwd(WORKDIR)

# Paketler
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
cat("v4 DIAGNOSTIC — Etiket Cross-Check + Mutual Information\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat(strrep("=", 78), "\n\n", sep = "")

# ===========================================================================
# BÖLÜM 1 — ETİKET CROSS-CHECK (THYAO v3 PREDICTIONS)
# ===========================================================================
cat("\n", strrep("-", 78), "\n", sep = "")
cat("BOLUM 1 — ETIKET CROSS-CHECK (THYAO v3)\n")
cat(strrep("-", 78), "\n", sep = "")

if (!file.exists(PRED_FILE)) {
  stop("HATA: v3 PREDICTIONS dosyasi bulunamadi: ", PRED_FILE)
}

pred_df <- read.csv(PRED_FILE, stringsAsFactors = FALSE)
cat(sprintf("Yuklendi: %d satir (val + test, 15 config)\n", nrow(pred_df)))

# Sadece test seti
test_df <- pred_df %>% filter(set == "test")
cat(sprintf("Test seti: %d tahmin (15 config x ~%d ornek)\n",
            nrow(test_df), nrow(test_df) / 15))

# Her config (lambda, seed) için: Acc(thr=0.5) ve flip-Acc
# flip-Acc: tahminleri ters çevir, Acc hesapla. Eşit data, sadece label flip.
label_check <- test_df %>%
  group_by(lambda, seed) %>%
  summarise(
    n_test        = n(),
    n_up_true     = sum(y_true == 1),
    n_down_true   = sum(y_true == 0),
    naive_acc     = max(mean(y_true == 1), mean(y_true == 0)),
    mean_yhat     = mean(yhat),
    sd_yhat       = sd(yhat),
    # Orijinal etiketle Acc (thr=0.5)
    acc_orig      = mean(as.integer(yhat > 0.5) == y_true),
    sens_orig     = sum(yhat > 0.5 & y_true == 1) / max(sum(y_true == 1), 1),
    spec_orig     = sum(yhat <= 0.5 & y_true == 0) / max(sum(y_true == 0), 1),
    # Flip — etiketler tersmiş gibi davran (matematiksel olarak 1 - acc_orig)
    acc_flip      = mean(as.integer(yhat > 0.5) == (1 - y_true)),
    .groups = "drop"
  ) %>%
  mutate(
    acc_diff       = acc_flip - acc_orig,
    flip_beats_naive = acc_flip > naive_acc,
    diagnosis = case_when(
      acc_flip > 0.55 & acc_orig < 0.45  ~ "BUG/CONTRARIAN: model sistematik ters",
      abs(acc_orig - 0.5) < 0.05         ~ "RANDOM: model fark yok",
      acc_orig > 0.55                    ~ "OK: model tahmin ediyor (forward)",
      TRUE                               ~ "BELIRSIZ"
    )
  )

# Lambda ortalamaları (5 seed)
label_check_summary <- label_check %>%
  group_by(lambda) %>%
  summarise(
    n_config         = n(),
    mean_acc_orig    = mean(acc_orig),
    mean_acc_flip    = mean(acc_flip),
    mean_acc_diff    = mean(acc_diff),
    n_flip_beats_naive = sum(flip_beats_naive),
    n_bug_diagnosis  = sum(diagnosis == "BUG/CONTRARIAN: model sistematik ters"),
    .groups = "drop"
  )

cat("\n--- Lambda ortalamasi (5 seed) ---\n")
print(label_check_summary)

cat("\n--- Tum 15 config ayrintili ---\n")
print(label_check %>% select(lambda, seed, acc_orig, acc_flip, acc_diff,
                              flip_beats_naive, diagnosis))

# Genel teşhis
overall_flip_beats <- sum(label_check$flip_beats_naive)
overall_bug_count  <- sum(label_check$diagnosis == "BUG/CONTRARIAN: model sistematik ters")

cat("\n--- OZET ---\n")
cat(sprintf("15 config'in %d/15'inde flip-Acc Naive'i geciyor.\n", overall_flip_beats))
cat(sprintf("15 config'in %d/15'i 'BUG/CONTRARIAN' tanisi aliyor.\n", overall_bug_count))

if (overall_bug_count >= 10) {
  cat("[!] CIDDI BULGU: Model sistematik ters tahmin yapiyor.\n")
  cat("    Onerilen aksiyon: v3 scriptindeki etiket tanimini cross-check et:\n")
  cat("      Mevcut: y(t) = (price[t+OUT_LEN] > price[t])\n")
  cat("      Kontrol: Up/Down tanimi dogru yonde mi? Off-by-one var mi?\n")
} else if (overall_flip_beats >= 10) {
  cat("[*] DIKKAT: Flip-Acc cogu config'de Naive'i geciyor.\n")
  cat("    BUG mu CONTRARIAN sinyal mi ayirt etmek icin literatur tarama gerek.\n")
} else {
  cat("[ ] OK: Model 'random' veya 'forward predictor' tanisi aliyor.\n")
  cat("    Acc=0.42 muhtemelen test seti boyut/varyans gurultusu.\n")
}

# Kaydet
write.csv(label_check, file.path(OUTDIR, "mcaware_v4_LABEL_CHECK.csv"),
          row.names = FALSE)
cat(sprintf("\nYazildi: mcaware_v4_LABEL_CHECK.csv (%d satir)\n", nrow(label_check)))

# ===========================================================================
# BÖLÜM 2 — MUTUAL INFORMATION (AMZ + THYAO)
# ===========================================================================
cat("\n", strrep("-", 78), "\n", sep = "")
cat("BOLUM 2 — MUTUAL INFORMATION (AMZ closing/full, THYAO closing/full)\n")
cat(strrep("-", 78), "\n", sep = "")

# infotheo paketi nat birimi döner; bit'e çevirme: nat / log(2)
nat_to_bit <- function(x) x / log(2)

# I(X;Y) joint estimator: discretize X (equalfreq, ~sqrt(N) bin) + binary y
estimate_mi <- function(X, y, varname) {
  X_df <- as.data.frame(X)
  # NA temizle (X veya y'de NA varsa hizalı şekilde çıkar)
  keep <- complete.cases(X_df) & !is.na(y)
  X_df <- X_df[keep, , drop = FALSE]
  y_vec <- as.integer(y[keep])
  nbins <- max(2L, min(20L, round(sqrt(nrow(X_df)))))
  X_disc <- infotheo::discretize(X_df, disc = "equalfreq", nbins = nbins)
  # y zaten 0/1 — discretize gerekmiyor, doğrudan vector ver
  mi_nat <- infotheo::mutinformation(X_disc, y_vec)
  list(varname = varname, n = nrow(X_df), n_features = ncol(X_df),
       nbins = nbins, mi_nat = mi_nat, mi_bit = nat_to_bit(mi_nat))
}

# --- 2.1 AMZ verisi yükle ---
mi_results <- list()
if (file.exists(AMZ_FILE)) {
  cat("AMZ verisi yukleniyor...\n")
  raw <- read_excel(AMZ_FILE)
  raw <- raw[!is.na(raw$Date), ]
  colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                     "Price_AZS", "LogReturn_AZS",
                     "Price_AMZ", "LogReturn_AMZ")
  for (c_ in c("Price_AMZ", "LogReturn_AMZ"))
    raw[[c_]] <- as.numeric(raw[[c_]])
  amz <- raw %>% filter(!is.na(Price_AMZ)) %>% select(Date, Close = Price_AMZ)

  # Feature engineering — v1.1 ile aynı set
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
  cat(sprintf("AMZ (warmup sonrasi): %d hafta\n", nrow(amz)))

  # Etiket: y(t) = price[t+3] > price[t]
  OUT_LEN <- 3L
  N <- nrow(amz)
  if (N > OUT_LEN + 1) {
    y_amz <- as.integer(amz$Close[(1 + OUT_LEN):N] > amz$Close[1:(N - OUT_LEN)])
    # Feature'lar t anında, etiket t+3'te → X[1..N-OUT_LEN], y eşleşir
    X_amz_full <- amz[1:(N - OUT_LEN), c("Close", "RSI", "MACD",
                                          "EMA12", "EMA26", "Momentum",
                                          "Volatility")]
    X_amz_closing <- amz[1:(N - OUT_LEN), "Close", drop = FALSE]
    # LogReturn ham — closing'in tek başına da test edilmesi için
    # NA temizliği estimate_mi içinde yapılıyor, hizalamaya gerek yok
    amz_logret <- c(NA, diff(log(amz$Close)))
    X_amz_logret <- data.frame(LogReturn = amz_logret[1:(N - OUT_LEN)])

    mi_results[["amz_closing_price"]] <- estimate_mi(X_amz_closing, y_amz,
                                                     "AMZ_closing_price_only")
    mi_results[["amz_closing_logret"]] <- estimate_mi(X_amz_logret, y_amz,
                                                      "AMZ_closing_logreturn_only")
    mi_results[["amz_full"]] <- estimate_mi(X_amz_full, y_amz, "AMZ_full_7feat")
  }
} else {
  cat("[!] AMZ dosyasi bulunamadi:", AMZ_FILE, "— AMZ MI hesabi atlaniyor.\n")
}

# --- 2.2 THYAO verisi (Yahoo Finance, hızlı çekim) ---
cat("\nTHYAO verisi cekiliyor (Yahoo Finance)...\n")
tryCatch({
  Sys.setenv(TZ = "UTC")
  getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  thyao_xts <- get("THYAO.IS")
  thyao_df <- data.frame(
    Date   = as.character(index(thyao_xts)),
    Open   = as.numeric(Op(thyao_xts)),
    High   = as.numeric(Hi(thyao_xts)),
    Low    = as.numeric(Lo(thyao_xts)),
    Close  = as.numeric(Cl(thyao_xts)),
    Volume = as.numeric(Vo(thyao_xts))
  )
  thyao_df <- thyao_df[thyao_df$Volume > 0, ]
  thyao_df <- thyao_df[complete.cases(thyao_df[, c("Open","High","Low","Close")]), ]
  cat(sprintf("THYAO: %d gun\n", nrow(thyao_df)))

  # Feature engineering — v3 ile (kısaltılmış)
  thyao_df$RSI   <- TTR::RSI(thyao_df$Close, n = 14)
  macd_vals      <- TTR::MACD(thyao_df$Close)
  thyao_df$MACD  <- macd_vals[, "macd"]
  thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n = 12)
  thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n = 26)
  thyao_df <- thyao_df[28:nrow(thyao_df), ] %>% drop_na()

  OUT_LEN <- 3L
  N <- nrow(thyao_df)
  y_thyao <- as.integer(thyao_df$Close[(1 + OUT_LEN):N] >
                          thyao_df$Close[1:(N - OUT_LEN)])
  X_thyao_full <- thyao_df[1:(N - OUT_LEN), c("Close", "Open", "Volume",
                                               "RSI", "MACD", "EMA12", "EMA26")]
  X_thyao_closing <- thyao_df[1:(N - OUT_LEN), "Close", drop = FALSE]
  thyao_logret <- c(NA, diff(log(thyao_df$Close)))
  X_thyao_logret <- data.frame(LogReturn = thyao_logret[1:(N - OUT_LEN)])

  mi_results[["thyao_closing_price"]] <- estimate_mi(X_thyao_closing, y_thyao,
                                                     "THYAO_closing_price_only")
  mi_results[["thyao_closing_logret"]] <- estimate_mi(X_thyao_logret, y_thyao,
                                                      "THYAO_closing_logreturn_only")
  mi_results[["thyao_full"]] <- estimate_mi(X_thyao_full, y_thyao,
                                             "THYAO_full_7feat")
}, error = function(e) {
  cat("[!] THYAO Yahoo cekilemedi:", conditionMessage(e), "\n")
  cat("    Internet baglantisi yok ise bu adim atlaniyor.\n")
})

# --- 2.3 MI sonuçlarını topla ve raporla ---
mi_df <- do.call(rbind, lapply(mi_results, function(r) {
  data.frame(dataset = r$varname, n = r$n, n_features = r$n_features,
             nbins = r$nbins, MI_nat = r$mi_nat, MI_bit = r$mi_bit,
             stringsAsFactors = FALSE)
}))

# Yorum ekle
if (!is.null(mi_df) && nrow(mi_df) > 0) {
  mi_df$interpretation <- case_when(
    mi_df$MI_bit < 0.01 ~ "ZERO_INFO: sinyal yok, MC matematiksel optimal",
    mi_df$MI_bit < 0.05 ~ "LOW: zayif sinyal, Naive zor gecilir",
    mi_df$MI_bit < 0.15 ~ "MODERATE: makul sinyal, model ogrenebilir",
    TRUE                ~ "HIGH: guclu sinyal"
  )

  cat("\n--- MI ozet tablo ---\n")
  print(mi_df)

  cat("\n--- YORUM ---\n")
  for (i in seq_len(nrow(mi_df))) {
    cat(sprintf("  %s : MI = %.4f bit (%s)\n",
                mi_df$dataset[i], mi_df$MI_bit[i], mi_df$interpretation[i]))
  }

  # Kaydet
  write.csv(mi_df, file.path(OUTDIR, "mcaware_v4_MI_SCORES.csv"),
            row.names = FALSE)
  cat(sprintf("\nYazildi: mcaware_v4_MI_SCORES.csv (%d satir)\n", nrow(mi_df)))
} else {
  cat("[!] Hicbir MI hesabi tamamlanamadi (AMZ ve THYAO erisilemedi).\n")
}

# ===========================================================================
# KAPANIŞ
# ===========================================================================
cat("\n", strrep("=", 78), "\n", sep = "")
cat("v4 DIAGNOSTIC TAMAMLANDI\n")
cat("Sonraki adim: PROJE_DURUMU.txt Bolum 10.18 olarak iki CSV'nin\n")
cat("yorumunu yaz ve hoca toplantisi (ADIM J) icin Bolum 11'i guncelle.\n")
cat(strrep("=", 78), "\n", sep = "")

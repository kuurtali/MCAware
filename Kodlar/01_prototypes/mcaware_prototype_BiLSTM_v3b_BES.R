# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v3b BES (ADIM I.6: ALZ + AZS + AMZ REPLİKASYON)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026 — v3b'nin haftalık BES verilerine UYARLAMASI
# ---------------------------------------------------------------------------
# AMACI:
#   v3 + v3b sonuçları: THYAO test setinde 30/30 anti-prediktif (p≈3e-5,
#   v3 Acc=0.418/flip=0.582, v3b Acc=0.396/flip=0.604). Anti-prediktif
#   davranış pencere tanımına dayanıklı çıktı. AMA tek varlık (THYAO).
#
#   AÇIK SORU (Bölüm 5, Q6): Anti-prediktif sadece THYAO'ya mı özgü, yoksa
#   BIST/BES genel bir örüntü mü?
#
#   Bu script v3b metodolojisini ALZ + AZS + AMZ (haftalık BES) verilerine
#   uygular ve flip_beats_naive testinin replike olup olmadığını ölçer.
#
# KARAR MATRİSİ (her varlık ayrı):
#   [A] AZS/AMZ'de flip_wins >= 12/15  → Anti-prediktif BIST/BES GENEL.
#                                         Yorum 3 (contrarian) GÜÇLÜ — 2-3
#                                         varlıkta replike olmuş anomali.
#   [B] AZS/AMZ'de flip_wins <= 7/15   → Anti-prediktif THYAO-SPESİFİK.
#                                         Yorum 3 dar kalır; iddia "günlük
#                                         BIST hissesinde gözlenen" diye
#                                         daraltılır.
#   [C] Karışık (biri 12+, biri 7-)    → Heterojen. Frekans veya likidite
#                                         etkisi olabilir; detaylı analiz.
#
#   ALZ NOTU: ALZ %100 Up → Spec=NaN, flip-Acc trivially anlamsız.
#             Yine de scripte dahil — DEGENERATE control. Modelin nasıl
#             saturate olduğu rapor edilir (yhat dağılımı, MC oranı).
#
# ÇIKTI: Her varlık için 4 CSV (PREDICTIONS, OPTIMAL, SUMMARY, YHAT_STATS) +
#        cross-fund özet (CROSS_FUND_SUMMARY).
#
# Çalıştırma: RStudio → Ctrl+Shift+S → ~45-60 dk → 13 CSV
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ---
WORKDIR <- here::here()
# [B18] OUTDIR <- here::here()
# --- B18 fix: Subdirectory tanimlari ---
OUTDIR_SUM  <- here::here("Sonuclar", "summaries")
OUTDIR_PRED <- here::here("Sonuclar", "predictions")
OUTDIR_THR  <- here::here("Sonuclar", "thresholds")
OUTDIR_DIAG <- here::here("Sonuclar", "diagnostics")
for (.d in c(OUTDIR_SUM, OUTDIR_PRED, OUTDIR_THR, OUTDIR_DIAG)) {
  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE)
}
DATA_FILE <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(readxl)
  library(keras3)
  library(tensorflow)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v3b BES (ADIM I.6 REPLIKASYON)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
 # ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v3b BES (ADIM I.6: ALZ + AZS + AMZ REPLİKASYON)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026 — v3b'nin haftalık BES verilerine UYARLAMASI
# ---------------------------------------------------------------------------
# AMACI:
#   v3 + v3b sonuçları: THYAO test setinde 30/30 anti-prediktif (p≈3e-5,
#   v3 Acc=0.418/flip=0.582, v3b Acc=0.396/flip=0.604). Anti-prediktif
#   davranış pencere tanımına dayanıklı çıktı. AMA tek varlık (THYAO).
#
#   AÇIK SORU (Bölüm 5, Q6): Anti-prediktif sadece THYAO'ya mı özgü, yoksa
#   BIST/BES genel bir örüntü mü?
#
#   Bu script v3b metodolojisini ALZ + AZS + AMZ (haftalık BES) verilerine
#   uygular ve flip_beats_naive testinin replike olup olmadığını ölçer.
#
# KARAR MATRİSİ (her varlık ayrı):
#   [A] AZS/AMZ'de flip_wins >= 12/15  → Anti-prediktif BIST/BES GENEL.
#                                         Yorum 3 (contrarian) GÜÇLÜ — 2-3
#                                         varlıkta replike olmuş anomali.
#   [B] AZS/AMZ'de flip_wins <= 7/15   → Anti-prediktif THYAO-SPESİFİK.
#                                         Yorum 3 dar kalır; iddia "günlük
#                                         BIST hissesinde gözlenen" diye
#                                         daraltılır.
#   [C] Karışık (biri 12+, biri 7-)    → Heterojen. Frekans veya likidite
#                                         etkisi olabilir; detaylı analiz.
#
#   ALZ NOTU: ALZ %100 Up → Spec=NaN, flip-Acc trivially anlamsız.
#             Yine de scripte dahil — DEGENERATE control. Modelin nasıl
#             saturate olduğu rapor edilir (yhat dağılımı, MC oranı).
#
# ÇIKTI: Her varlık için 4 CSV (PREDICTIONS, OPTIMAL, SUMMARY, YHAT_STATS) +
#        cross-fund özet (CROSS_FUND_SUMMARY).
#
# Çalıştırma: RStudio → Ctrl+Shift+S → ~45-60 dk → 13 CSV
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ---
WORKDIR <- here::here()
DATA_FILE <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(readxl)
  library(keras3)
  library(tensorflow)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v3b BES (ADIM I.6 REPLIKASYON)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("Varliklar: ALZ (degen kontrol) + AZS + AMZ\n")
cat("Pencere: feats[(t-IN+1):t] (anchor gunu DAHIL, v3b ile ayni)\n")
cat("========================================================================\n\n")

if (!file.exists(DATA_FILE)) {
  stop("HATA: BES veri dosyasi yok: ", DATA_FILE)
}
# [B18] if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR'a kayit: ", WORKDIR)
# [B18]   OUTDIR <- WORKDIR
}

# --- 0a. Bidirectional API tespiti ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else {
  stop("keras3 bidirectional API bulunamadi.")
}

# --- 1. BES verisini yukle ve uc fonu ayikla ---
raw <- read_excel(DATA_FILE)
raw <- raw[!is.na(raw$Date), ]
colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                   "Price_AZS", "LogReturn_AZS",
                   "Price_AMZ", "LogReturn_AMZ")
for (c_ in c("Price_ALZ","Price_AZS","Price_AMZ",
             "LogReturn_ALZ","LogReturn_AZS","LogReturn_AMZ")) {
  raw[[c_]] <- as.numeric(raw[[c_]])
}
cat(sprintf("Ham veri: %d hafta (BES, 2021-2026)\n\n", nrow(raw)))

build_fund_df <- function(price_col_name) {
  df <- raw %>%
    filter(!is.na(.data[[price_col_name]])) %>%
    select(Date, Close = all_of(price_col_name))
  df$RSI       <- TTR::RSI(df$Close, n = 14)
  ema12        <- TTR::EMA(df$Close, n = 12)
  ema26        <- TTR::EMA(df$Close, n = 26)
  df$MACD      <- ema12 - ema26
  df$EMA12     <- ema12
  df$EMA26     <- ema26
  df$Momentum  <- df$Close / dplyr::lag(df$Close, 14) - 1
  df$Volatility <- zoo::rollapply(c(NA, diff(log(df$Close))),
                                   width = 14, FUN = stats::sd,
                                   fill = NA, align = "right")
  df %>% drop_na()
}

# --- 2. Loss + model insasi (v3b ile AYNI) ---
make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) {
      mean_pred  <- keras3::op_mean(y_pred)
      mc_penalty <- keras3::op_abs(mean_pred - 0.5)
      bce + lambda_mc * mc_penalty
    } else {
      bce
    }
  }
}

build_bilstm <- function(seed, lambda_mc, in_len, f_dim) {
  keras3::set_random_seed(seed)
  inner_lstm <- keras3::layer_lstm(units = 64, activation = "tanh",
                                    return_sequences = FALSE)
  model <- keras3::keras_model_sequential(input_shape = c(in_len, f_dim))
  model <- bidir_fn(model, inner_lstm, merge_mode = "concat")
  model <- model %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(
    optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc),
    metrics = c("accuracy")
  )
  model
}

# --- 3. Metrik hesabi (v3b ile AYNI, flip-Acc dahil) ---
compute_metrics <- function(y_true, yhat, threshold) {
  pred <- as.integer(yhat > threshold)
  tp <- sum(pred == 1 & y_true == 1)
  tn <- sum(pred == 0 & y_true == 0)
  fp <- sum(pred == 1 & y_true == 0)
  fn <- sum(pred == 0 & y_true == 1)
  n  <- length(y_true)
  acc  <- (tp + tn) / n
  sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
  prec_ <- if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
  f1   <- if (!is.na(prec_) && !is.na(sens) && (prec_ + sens) > 0)
            2 * prec_ * sens / (prec_ + sens) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) ||
           is.na(spec) || is.na(sens)
  acc_flip <- 1 - acc
  list(Acc = acc, Sens = sens, Spec = spec, Prec = prec_,
       F1 = f1, BalAcc = bacc, is_MC = is_mc, Acc_flip = acc_flip,
       n_pred_Up = sum(pred), n_pred_Down = n - sum(pred))
}

# --- 4. Grid ---
IN_LEN     <- 2L
OUT_LEN    <- 3L
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)
feat_cols  <- c("Close", "RSI", "MACD", "EMA12", "EMA26", "Momentum", "Volatility")
F_DIM      <- length(feat_cols)

# --- 5. Tek fon uzerinde calisan ana fonksiyon ---
run_fund <- function(fund_name, fund_df) {
  cat("\n", strrep("=", 80), "\n", sep = "")
  cat(sprintf("FON: %s — %d hafta (warmup sonrasi)\n", fund_name, nrow(fund_df)))
  cat(strrep("=", 80), "\n", sep = "")

  # Pencereleme
  feats  <- as.matrix(fund_df[, feat_cols])
  prices <- fund_df$Close
  N <- nrow(feats)
  if (N < IN_LEN + OUT_LEN + 10) {
    cat(sprintf("[!] %s: yetersiz veri (%d), atlaniyor.\n", fund_name, N))
    return(NULL)
  }
  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN + 1):(N - OUT_LEN)) {
    X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
    y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec
  cat(sprintf("Pencere sayisi: %d | Up oran: %.1f%% Down oran: %.1f%%\n",
              length(y_arr), 100*mean(y_arr), 100*(1-mean(y_arr))))

  # ALZ kontrolu: tum y=1 ise model bilgi-icermeyen MC olur, raporla
  is_degenerate <- (mean(y_arr) == 1) || (mean(y_arr) == 0)
  if (is_degenerate) {
    cat("[!] DEGENERATE: tek sinif (%100 Up veya %100 Down) - flip-Acc anlamsiz.\n")
    cat("    Yine de model egitilecek, yhat dagilimi raporlanacak.\n")
  }

  # Split
  n_total <- length(y_arr)
  i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
  X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
  X_te <- X_arr[(i_va+1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va+1L):n_total]
  cat(sprintf("Split: Egitim=%d Dogrulama=%d Test=%d\n",
              length(y_tr), length(y_va), length(y_te)))
  cat(sprintf("Train Up=%.1f%% Val Up=%.1f%% Test Up=%.1f%%\n",
              100*mean(y_tr), 100*mean(y_va), 100*mean(y_te)))

  # class_weight (balanced) - degenerate ise NULL
  if (is_degenerate || sum(y_tr == 0) == 0 || sum(y_tr == 1) == 0) {
    cw <- NULL
    cat("class_weight: NULL (degenerate train set)\n")
  } else {
    n_up <- sum(y_tr == 1); n_down <- sum(y_tr == 0); n_train <- length(y_tr)
    cw <- list("0" = n_train / (2 * n_down), "1" = n_train / (2 * n_up))
    cat(sprintf("class_weight: Down=%.3f Up=%.3f (balanced)\n", cw[["0"]], cw[["1"]]))
  }

  # Naive
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
  cat(sprintf("NAIVE BASELINE: Acc = %.4f\n", naive_acc))

  # Normalize (train-only)
  mu_arr <- apply(X_tr, c(2,3), mean)
  sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
  X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

  # Grid
  predictions_list <- list()
  optimal_rows     <- list()
  yhat_stats_rows  <- list()

  t0 <- Sys.time()
  for (lam in LAMBDAS) {
    for (sd_seed in SEEDS) {
      cat(sprintf("\n[%s] lambda=%.2f seed=%d ...\n", fund_name, lam, sd_seed))
      keras3::clear_session()
      pred <- tryCatch({
        model <- build_bilstm(sd_seed, lam, IN_LEN, F_DIM)
        cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                               patience = 5L,
                                               restore_best_weights = TRUE)
        fit_args <- list(
          object = model, X_tr, y_tr,
          validation_data = list(X_va, y_va),
          epochs = 50L, batch_size = 32L, verbose = 0L,
          callbacks = list(cb)
        )
        if (!is.null(cw)) fit_args$class_weight <- cw
        do.call(keras3::fit, fit_args)
        yhat_val  <- as.numeric(predict(model, X_va, verbose = 0L))
        yhat_test <- as.numeric(predict(model, X_te, verbose = 0L))
        list(yhat_val = yhat_val, yhat_test = yhat_test, error = NA_character_)
      }, error = function(e) {
        list(yhat_val = rep(NA_real_, length(y_va)),
             yhat_test = rep(NA_real_, length(y_te)),
             error = conditionMessage(e))
      })
      if (!is.na(pred$error)) {
        cat("  HATA:", pred$error, "\n"); next
      }

      yhat_stats_rows[[length(yhat_stats_rows) + 1]] <- data.frame(
        fund = fund_name, lambda = lam, seed = sd_seed,
        test_min = min(pred$yhat_test), test_max = max(pred$yhat_test),
        test_mean = mean(pred$yhat_test), test_sd = stats::sd(pred$yhat_test),
        test_range = max(pred$yhat_test) - min(pred$yhat_test),
        stringsAsFactors = FALSE
      )

      # Predictions log
      for (i in seq_along(y_te)) {
        predictions_list[[length(predictions_list) + 1]] <- data.frame(
          fund = fund_name, lambda = lam, seed = sd_seed,
          sample_id = i, yhat = pred$yhat_test[i], y_true = y_te[i],
          stringsAsFactors = FALSE
        )
      }

      m_test_05 <- compute_metrics(y_te, pred$yhat_test, 0.5)
      optimal_rows[[length(optimal_rows) + 1]] <- data.frame(
        fund = fund_name, lambda = lam, seed = sd_seed,
        naive_acc = naive_acc,
        test_Acc_05 = m_test_05$Acc, test_Spec_05 = m_test_05$Spec,
        test_Sens_05 = m_test_05$Sens, test_BalAcc_05 = m_test_05$BalAcc,
        test_Acc_flip_05 = m_test_05$Acc_flip,
        test_flip_beats_naive_05 = isTRUE(m_test_05$Acc_flip > naive_acc),
        test_is_MC_05 = m_test_05$is_MC,
        is_degenerate = is_degenerate,
        stringsAsFactors = FALSE
      )

      cat(sprintf("  Acc=%.3f Spec=%.3f Sens=%.3f Acc_flip=%.3f Naive=%.3f flip_beats=%s MC=%s\n",
                  m_test_05$Acc, m_test_05$Spec, m_test_05$Sens,
                  m_test_05$Acc_flip, naive_acc,
                  if (isTRUE(m_test_05$Acc_flip > naive_acc)) "YES" else "no",
                  if (m_test_05$is_MC) "YES" else "no"))
    }
  }
  t1 <- Sys.time()
  cat(sprintf("\n[%s] sure: %.1f dakika\n", fund_name,
              as.numeric(difftime(t1, t0, units = "mins"))))

  # DataFrame'lere donustur
  predictions_df <- do.call(rbind, predictions_list)
  optimal_df     <- do.call(rbind, optimal_rows)
  yhat_stats_df  <- do.call(rbind, yhat_stats_rows)

  summary_df <- optimal_df %>%
    group_by(fund, lambda) %>%
    summarise(
      n_seeds = dplyr::n(),
      naive_acc = first(naive_acc),
      Acc_05  = mean(test_Acc_05, na.rm = TRUE),
      Spec_05 = mean(test_Spec_05, na.rm = TRUE),
      Sens_05 = mean(test_Sens_05, na.rm = TRUE),
      BalAcc_05 = mean(test_BalAcc_05, na.rm = TRUE),
      Acc_flip_05 = mean(test_Acc_flip_05, na.rm = TRUE),
      flip_beats_naive_count = sum(test_flip_beats_naive_05, na.rm = TRUE),
      MC_05   = sum(test_is_MC_05, na.rm = TRUE),
      .groups = "drop"
    )

  cat("\n[", fund_name, "] ozet (thr=0.5):\n", sep = "")
  print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05,
                               Acc_flip_05, flip_beats_naive_count, MC_05))

  # CSV kaydet
  fp <- function(suf) file.path(OUTDIR_SUM,
    sprintf("mcaware_BiLSTM_v3b_BES_%s_%s.csv", fund_name, suf))
  write.csv(predictions_df, fp("PREDICTIONS"), row.names = FALSE)
  write.csv(optimal_df,     fp("OPTIMAL"),     row.names = FALSE)
  write.csv(summary_df,     fp("SUMMARY"),     row.names = FALSE)
  write.csv(yhat_stats_df,  fp("YHAT_STATS"),  row.names = FALSE)
  cat(sprintf("[%s] 4 CSV kaydedildi.\n", fund_name))

  optimal_df  # cross-fund ozet icin geri don
}

# --- 6. Uc fonu sirayla calistir ---
cat("\nFON HAZIRLIGI...\n")
alz_df <- build_fund_df("Price_ALZ")
azs_df <- build_fund_df("Price_AZS")
amz_df <- build_fund_df("Price_AMZ")
cat(sprintf("ALZ: %d hafta | AZS: %d hafta | AMZ: %d hafta\n\n",
            nrow(alz_df), nrow(azs_df), nrow(amz_df)))

all_optimal <- list()
all_optimal[["ALZ"]] <- run_fund("ALZ", alz_df)
all_optimal[["AZS"]] <- run_fund("AZS", azs_df)
all_optimal[["AMZ"]] <- run_fund("AMZ", amz_df)

# --- 7. Cross-fund ozet + karar matrisi ---
cat("\n\n", strrep("=", 80), "\n", sep = "")
cat("CROSS-FUND OZET (ADIM I.6 KARAR MATRISI)\n")
cat(strrep("=", 80), "\n", sep = "")

cross_rows <- list()
for (fn in names(all_optimal)) {
  d <- all_optimal[[fn]]
  if (is.null(d)) next
  cross_rows[[length(cross_rows) + 1]] <- data.frame(
    fund = fn,
    n_config = nrow(d),
    naive_acc = first(d$naive_acc),
    mean_acc = mean(d$test_Acc_05, na.rm = TRUE),
    mean_acc_flip = mean(d$test_Acc_flip_05, na.rm = TRUE),
    flip_beats_naive_count = sum(d$test_flip_beats_naive_05, na.rm = TRUE),
    mc_count = sum(d$test_is_MC_05, na.rm = TRUE),
    is_degenerate = first(d$is_degenerate),
    stringsAsFactors = FALSE
  )
}
cross_df <- do.call(rbind, cross_rows)
print(cross_df)

# THYAO referans (Bolum 10.23'ten):
cat("\nTHYAO REFERANSI (v3b, gunluk):\n")
cat("  fund=THYAO n_config=15 naive=0.518 mean_acc=0.396 mean_acc_flip=0.604\n")
cat("  flip_beats_naive=15/15 (p ~ 3e-5)\n\n")

# Karar
get_dir <- function(flip_wins, n_cfg, is_deg) {
  if (is_deg) return("DEGENERATE (tek sinif)")
  if (flip_wins >= 12) return("[A] BIST/BES GENEL anti-prediktif (Yorum 3 guclu)")
  if (flip_wins <= 7)  return("[B] varlik-spesifik (Yorum 3 dar)")
  return("[C] heterojen, sinir bolge")
}
for (i in seq_len(nrow(cross_df))) {
  cat(sprintf("  %s : flip_wins=%d/%d -> %s\n",
              cross_df$fund[i], cross_df$flip_beats_naive_count[i],
              cross_df$n_config[i],
              get_dir(cross_df$flip_beats_naive_count[i],
                      cross_df$n_config[i], cross_df$is_degenerate[i])))
}

write.csv(cross_df,
          file.path(OUTDIR_SUM, "mcaware_BiLSTM_v3b_BES_CROSS_FUND_SUMMARY.csv"),
          row.names = FALSE)
cat("\nCROSS_FUND_SUMMARY kaydedildi.\n")
cat("\nADIM I.6 TAMAMLANDI — sonuclari PROJE_DURUMU.txt Bolum 10.26 olarak isle.\n")
.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' 
cat("Varliklar: ALZ (degen kontrol) + AZS + AMZ\n")
cat("Pencere: feats[(t-IN+1):t] (anchor gunu DAHIL, v3b ile ayni)\n")
cat("========================================================================\n\n")

if (!file.exists(DATA_FILE)) {
  stop("HATA: BES veri dosyasi yok: ", DATA_FILE)
}
# [B18] if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR'a kayit: ", WORKDIR)
# [B18]   OUTDIR <- WORKDIR
}

# --- 0a. Bidirectional API tespiti ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else {
  stop("keras3 bidirectional API bulunamadi.")
}

# --- 1. BES verisini yukle ve uc fonu ayikla ---
raw <- read_excel(DATA_FILE)
raw <- raw[!is.na(raw$Date), ]
colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                   "Price_AZS", "LogReturn_AZS",
                   "Price_AMZ", "LogReturn_AMZ")
for (c_ in c("Price_ALZ","Price_AZS","Price_AMZ",
             "LogReturn_ALZ","LogReturn_AZS","LogReturn_AMZ")) {
  raw[[c_]] <- as.numeric(raw[[c_]])
}
cat(sprintf("Ham veri: %d hafta (BES, 2021-2026)\n\n", nrow(raw)))

build_fund_df <- function(price_col_name) {
  df <- raw %>%
    filter(!is.na(.data[[price_col_name]])) %>%
    select(Date, Close = all_of(price_col_name))
  df$RSI       <- TTR::RSI(df$Close, n = 14)
  ema12        <- TTR::EMA(df$Close, n = 12)
  ema26        <- TTR::EMA(df$Close, n = 26)
  df$MACD      <- ema12 - ema26
  df$EMA12     <- ema12
  df$EMA26     <- ema26
  df$Momentum  <- df$Close / dplyr::lag(df$Close, 14) - 1
  df$Volatility <- zoo::rollapply(c(NA, diff(log(df$Close))),
                                   width = 14, FUN = stats::sd,
                                   fill = NA, align = "right")
  df %>% drop_na()
}

# --- 2. Loss + model insasi (v3b ile AYNI) ---
make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) {
      mean_pred  <- keras3::op_mean(y_pred)
      mc_penalty <- keras3::op_abs(mean_pred - 0.5)
      bce + lambda_mc * mc_penalty
    } else {
      bce
    }
  }
}

build_bilstm <- function(seed, lambda_mc, in_len, f_dim) {
  keras3::set_random_seed(seed)
  inner_lstm <- keras3::layer_lstm(units = 64, activation = "tanh",
                                    return_sequences = FALSE)
  model <- keras3::keras_model_sequential(input_shape = c(in_len, f_dim))
  model <- bidir_fn(model, inner_lstm, merge_mode = "concat")
  model <- model %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(
    optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc),
    metrics = c("accuracy")
  )
  model
}

# --- 3. Metrik hesabi (v3b ile AYNI, flip-Acc dahil) ---
compute_metrics <- function(y_true, yhat, threshold) {
  pred <- as.integer(yhat > threshold)
  tp <- sum(pred == 1 & y_true == 1)
  tn <- sum(pred == 0 & y_true == 0)
  fp <- sum(pred == 1 & y_true == 0)
  fn <- sum(pred == 0 & y_true == 1)
  n  <- length(y_true)
  acc  <- (tp + tn) / n
  sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
  prec_ <- if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
  f1   <- if (!is.na(prec_) && !is.na(sens) && (prec_ + sens) > 0)
            2 * prec_ * sens / (prec_ + sens) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) ||
           is.na(spec) || is.na(sens)
  acc_flip <- 1 - acc
  list(Acc = acc, Sens = sens, Spec = spec, Prec = prec_,
       F1 = f1, BalAcc = bacc, is_MC = is_mc, Acc_flip = acc_flip,
       n_pred_Up = sum(pred), n_pred_Down = n - sum(pred))
}

# --- 4. Grid ---
IN_LEN     <- 2L
OUT_LEN    <- 3L
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)
feat_cols  <- c("Close", "RSI", "MACD", "EMA12", "EMA26", "Momentum", "Volatility")
F_DIM      <- length(feat_cols)

# --- 5. Tek fon uzerinde calisan ana fonksiyon ---
run_fund <- function(fund_name, fund_df) {
  cat("\n", strrep("=", 80), "\n", sep = "")
  cat(sprintf("FON: %s — %d hafta (warmup sonrasi)\n", fund_name, nrow(fund_df)))
  cat(strrep("=", 80), "\n", sep = "")

  # Pencereleme
  feats  <- as.matrix(fund_df[, feat_cols])
  prices <- fund_df$Close
  N <- nrow(feats)
  if (N < IN_LEN + OUT_LEN + 10) {
    cat(sprintf("[!] %s: yetersiz veri (%d), atlaniyor.\n", fund_name, N))
    return(NULL)
  }
  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN + 1):(N - OUT_LEN)) {
    X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
    y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec
  cat(sprintf("Pencere sayisi: %d | Up oran: %.1f%% Down oran: %.1f%%\n",
              length(y_arr), 100*mean(y_arr), 100*(1-mean(y_arr))))

  # ALZ kontrolu: tum y=1 ise model bilgi-icermeyen MC olur, raporla
  is_degenerate <- (mean(y_arr) == 1) || (mean(y_arr) == 0)
  if (is_degenerate) {
    cat("[!] DEGENERATE: tek sinif (%100 Up veya %100 Down) - flip-Acc anlamsiz.\n")
    cat("    Yine de model egitilecek, yhat dagilimi raporlanacak.\n")
  }

  # Split
  n_total <- length(y_arr)
  i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
  X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
  X_te <- X_arr[(i_va+1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va+1L):n_total]
  cat(sprintf("Split: Egitim=%d Dogrulama=%d Test=%d\n",
              length(y_tr), length(y_va), length(y_te)))
  cat(sprintf("Train Up=%.1f%% Val Up=%.1f%% Test Up=%.1f%%\n",
              100*mean(y_tr), 100*mean(y_va), 100*mean(y_te)))

  # class_weight (balanced) - degenerate ise NULL
  if (is_degenerate || sum(y_tr == 0) == 0 || sum(y_tr == 1) == 0) {
    cw <- NULL
    cat("class_weight: NULL (degenerate train set)\n")
  } else {
    n_up <- sum(y_tr == 1); n_down <- sum(y_tr == 0); n_train <- length(y_tr)
    cw <- list("0" = n_train / (2 * n_down), "1" = n_train / (2 * n_up))
    cat(sprintf("class_weight: Down=%.3f Up=%.3f (balanced)\n", cw[["0"]], cw[["1"]]))
  }

  # Naive
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
  cat(sprintf("NAIVE BASELINE: Acc = %.4f\n", naive_acc))

  # Normalize (train-only)
  mu_arr <- apply(X_tr, c(2,3), mean)
  sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
  X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

  # Grid
  predictions_list <- list()
  optimal_rows     <- list()
  yhat_stats_rows  <- list()

  t0 <- Sys.time()
  for (lam in LAMBDAS) {
    for (sd_seed in SEEDS) {
      cat(sprintf("\n[%s] lambda=%.2f seed=%d ...\n", fund_name, lam, sd_seed))
      keras3::clear_session()
      pred <- tryCatch({
        model <- build_bilstm(sd_seed, lam, IN_LEN, F_DIM)
        cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                               patience = 5L,
                                               restore_best_weights = TRUE)
        fit_args <- list(
          object = model, X_tr, y_tr,
          validation_data = list(X_va, y_va),
          epochs = 50L, batch_size = 32L, verbose = 0L,
          callbacks = list(cb)
        )
        if (!is.null(cw)) fit_args$class_weight <- cw
        do.call(keras3::fit, fit_args)
        yhat_val  <- as.numeric(predict(model, X_va, verbose = 0L))
        yhat_test <- as.numeric(predict(model, X_te, verbose = 0L))
        list(yhat_val = yhat_val, yhat_test = yhat_test, error = NA_character_)
      }, error = function(e) {
        list(yhat_val = rep(NA_real_, length(y_va)),
             yhat_test = rep(NA_real_, length(y_te)),
             error = conditionMessage(e))
      })
      if (!is.na(pred$error)) {
        cat("  HATA:", pred$error, "\n"); next
      }

      yhat_stats_rows[[length(yhat_stats_rows) + 1]] <- data.frame(
        fund = fund_name, lambda = lam, seed = sd_seed,
        test_min = min(pred$yhat_test), test_max = max(pred$yhat_test),
        test_mean = mean(pred$yhat_test), test_sd = stats::sd(pred$yhat_test),
        test_range = max(pred$yhat_test) - min(pred$yhat_test),
        stringsAsFactors = FALSE
      )

      # Predictions log
      for (i in seq_along(y_te)) {
        predictions_list[[length(predictions_list) + 1]] <- data.frame(
          fund = fund_name, lambda = lam, seed = sd_seed,
          sample_id = i, yhat = pred$yhat_test[i], y_true = y_te[i],
          stringsAsFactors = FALSE
        )
      }

      m_test_05 <- compute_metrics(y_te, pred$yhat_test, 0.5)
      optimal_rows[[length(optimal_rows) + 1]] <- data.frame(
        fund = fund_name, lambda = lam, seed = sd_seed,
        naive_acc = naive_acc,
        test_Acc_05 = m_test_05$Acc, test_Spec_05 = m_test_05$Spec,
        test_Sens_05 = m_test_05$Sens, test_BalAcc_05 = m_test_05$BalAcc,
        test_Acc_flip_05 = m_test_05$Acc_flip,
        test_flip_beats_naive_05 = isTRUE(m_test_05$Acc_flip > naive_acc),
        test_is_MC_05 = m_test_05$is_MC,
        is_degenerate = is_degenerate,
        stringsAsFactors = FALSE
      )

      cat(sprintf("  Acc=%.3f Spec=%.3f Sens=%.3f Acc_flip=%.3f Naive=%.3f flip_beats=%s MC=%s\n",
                  m_test_05$Acc, m_test_05$Spec, m_test_05$Sens,
                  m_test_05$Acc_flip, naive_acc,
                  if (isTRUE(m_test_05$Acc_flip > naive_acc)) "YES" else "no",
                  if (m_test_05$is_MC) "YES" else "no"))
    }
  }
  t1 <- Sys.time()
  cat(sprintf("\n[%s] sure: %.1f dakika\n", fund_name,
              as.numeric(difftime(t1, t0, units = "mins"))))

  # DataFrame'lere donustur
  predictions_df <- do.call(rbind, predictions_list)
  optimal_df     <- do.call(rbind, optimal_rows)
  yhat_stats_df  <- do.call(rbind, yhat_stats_rows)

  summary_df <- optimal_df %>%
    group_by(fund, lambda) %>%
    summarise(
      n_seeds = dplyr::n(),
      naive_acc = first(naive_acc),
      Acc_05  = mean(test_Acc_05, na.rm = TRUE),
      Spec_05 = mean(test_Spec_05, na.rm = TRUE),
      Sens_05 = mean(test_Sens_05, na.rm = TRUE),
      BalAcc_05 = mean(test_BalAcc_05, na.rm = TRUE),
      Acc_flip_05 = mean(test_Acc_flip_05, na.rm = TRUE),
      flip_beats_naive_count = sum(test_flip_beats_naive_05, na.rm = TRUE),
      MC_05   = sum(test_is_MC_05, na.rm = TRUE),
      .groups = "drop"
    )

  cat("\n[", fund_name, "] ozet (thr=0.5):\n", sep = "")
  print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05,
                               Acc_flip_05, flip_beats_naive_count, MC_05))

  # CSV kaydet
  fp <- function(suf) file.path(OUTDIR_SUM,
    sprintf("mcaware_BiLSTM_v3b_BES_%s_%s.csv", fund_name, suf))
  write.csv(predictions_df, fp("PREDICTIONS"), row.names = FALSE)
  write.csv(optimal_df,     fp("OPTIMAL"),     row.names = FALSE)
  write.csv(summary_df,     fp("SUMMARY"),     row.names = FALSE)
  write.csv(yhat_stats_df,  fp("YHAT_STATS"),  row.names = FALSE)
  cat(sprintf("[%s] 4 CSV kaydedildi.\n", fund_name))

  optimal_df  # cross-fund ozet icin geri don
}

# --- 6. Uc fonu sirayla calistir ---
cat("\nFON HAZIRLIGI...\n")
alz_df <- build_fund_df("Price_ALZ")
azs_df <- build_fund_df("Price_AZS")
amz_df <- build_fund_df("Price_AMZ")
cat(sprintf("ALZ: %d hafta | AZS: %d hafta | AMZ: %d hafta\n\n",
            nrow(alz_df), nrow(azs_df), nrow(amz_df)))

all_optimal <- list()
all_optimal[["ALZ"]] <- run_fund("ALZ", alz_df)
all_optimal[["AZS"]] <- run_fund("AZS", azs_df)
all_optimal[["AMZ"]] <- run_fund("AMZ", amz_df)

# --- 7. Cross-fund ozet + karar matrisi ---
cat("\n\n", strrep("=", 80), "\n", sep = "")
cat("CROSS-FUND OZET (ADIM I.6 KARAR MATRISI)\n")
cat(strrep("=", 80), "\n", sep = "")

cross_rows <- list()
for (fn in names(all_optimal)) {
  d <- all_optimal[[fn]]
  if (is.null(d)) next
  cross_rows[[length(cross_rows) + 1]] <- data.frame(
    fund = fn,
    n_config = nrow(d),
    naive_acc = first(d$naive_acc),
    mean_acc = mean(d$test_Acc_05, na.rm = TRUE),
    mean_acc_flip = mean(d$test_Acc_flip_05, na.rm = TRUE),
    flip_beats_naive_count = sum(d$test_flip_beats_naive_05, na.rm = TRUE),
    mc_count = sum(d$test_is_MC_05, na.rm = TRUE),
    is_degenerate = first(d$is_degenerate),
    stringsAsFactors = FALSE
  )
}
cross_df <- do.call(rbind, cross_rows)
print(cross_df)

# THYAO referans (Bolum 10.23'ten):
cat("\nTHYAO REFERANSI (v3b, gunluk):\n")
cat("  fund=THYAO n_config=15 naive=0.518 mean_acc=0.396 mean_acc_flip=0.604\n")
cat("  flip_beats_naive=15/15 (p ~ 3e-5)\n\n")

# Karar
get_dir <- function(flip_wins, n_cfg, is_deg) {
  if (is_deg) return("DEGENERATE (tek sinif)")
  if (flip_wins >= 12) return("[A] BIST/BES GENEL anti-prediktif (Yorum 3 guclu)")
  if (flip_wins <= 7)  return("[B] varlik-spesifik (Yorum 3 dar)")
  return("[C] heterojen, sinir bolge")
}
for (i in seq_len(nrow(cross_df))) {
  cat(sprintf("  %s : flip_wins=%d/%d -> %s\n",
              cross_df$fund[i], cross_df$flip_beats_naive_count[i],
              cross_df$n_config[i],
              get_dir(cross_df$flip_beats_naive_count[i],
                      cross_df$n_config[i], cross_df$is_degenerate[i])))
}

write.csv(cross_df,
          file.path(OUTDIR_SUM, "mcaware_BiLSTM_v3b_BES_CROSS_FUND_SUMMARY.csv"),
          row.names = FALSE)
cat("\nCROSS_FUND_SUMMARY kaydedildi.\n")
cat("\nADIM I.6 TAMAMLANDI — sonuclari PROJE_DURUMU.txt Bolum 10.26 olarak isle.\n")

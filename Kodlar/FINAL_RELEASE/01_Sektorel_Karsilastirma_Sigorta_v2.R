# ===========================================================================
# MC-AWARE — BIST-5 SIGORTA v2 (SEED FIX + DERIN EGITIM) — DENEY I.22
# TUBITAK 2209-A — Yurutucu: Mehmet Ali KURT
# Olusturulma: 23 Mayis 2026 (v3 sonradan ek)
# ---------------------------------------------------------------------------
# AMACI:
#   v1 (mcaware_bist5_sigorta_RESULTS.csv) seedler arasi IDENTICAL sonuc
#   uretti (KCHOL/SAHOL std=0, AKGRT/RAYSG std=0.0025). Bu, kucuk model +
#   erken durdurma + IN_LEN=2 kombinasyonunun parametre uzayini yeterince
#   kesfetmedigine isaret eder. Bu v2:
#     (a) 3 katmanli seed sabitleme (set.seed + tf$random$set_seed + py_set_seed)
#     (b) Erken durdurmayi gevsetir (patience 5 → 10)
#     (c) min_delta ekler (premature stop'u azaltir)
#     (d) Daha cok seed (3 → 5)
#     (e) Glorot init explicit seed ile her seed'de farkli init
#   ile yeniden kosturulup gercek seed-varyansi olculur. Eger v2'de de
#   std~0 cikarsa, bu modelin kapasitesi degil, verinin determinizm seviyesi
#   sorunudur ve "seed-bagimsiz" sonuc bulgu olarak raporlanir.
#
# CIKTI: mcaware_bist5_sigorta_v2_RESULTS.csv + _SUMMARY.csv
# Sure: ~60-90 dk
# ===========================================================================

WORKDIR <- "C:/Users/Kurt/Desktop"
OUTDIR  <- "C:/Users/Kurt/Desktop/Proje/00_Tubitak/Sonuclar"
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(keras3)
  library(tensorflow)
  library(reticulate)
  library(quantmod)
  library(rpart)
})

.ns <- asNamespace("keras3")
bidir_fn <- if (exists("bidirectional", envir = .ns)) get("bidirectional", envir = .ns) else get("layer_bidirectional", envir = .ns)

# --- 3 KATMANLI SEED SABITLEME ---
set_full_seed <- function(seed) {
  set.seed(seed)
  Sys.setenv(PYTHONHASHSEED = as.character(seed))
  tryCatch({
    reticulate::py_set_seed(seed, disable_hash_randomization = TRUE)
  }, error = function(e) cat("py_set_seed atlandi:", conditionMessage(e), "\n"))
  tryCatch({
    tensorflow::tf$random$set_seed(as.integer(seed))
  }, error = function(e) cat("tf$random$set_seed atlandi:", conditionMessage(e), "\n"))
  keras3::set_random_seed(as.integer(seed))
}

make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    else bce
  }
}

compute_metrics <- function(y_true, yhat, threshold = 0.5) {
  pred <- as.integer(yhat > threshold)
  tp <- sum(pred == 1 & y_true == 1); tn <- sum(pred == 0 & y_true == 0)
  fp <- sum(pred == 1 & y_true == 0); fn <- sum(pred == 0 & y_true == 1)
  n <- length(y_true); acc <- (tp + tn) / n
  sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) || is.na(spec) || is.na(sens)
  list(Acc = acc, Sens = sens, Spec = spec, is_MC = is_mc, Acc_flip = 1 - acc,
       n_pred_up = sum(pred == 1), n_pred_dn = sum(pred == 0))
}

test_stock_v2 <- function(ticker, from = "2020-01-01", to = "2026-03-31",
                          SEEDS = c(23L, 42L, 98L, 137L, 271L)) {
  cat(sprintf("\n%s\nHISSE: %s (v2)\n%s\n", strrep("=", 80), ticker, strrep("=", 80)))

  tryCatch({
    getSymbols(ticker, from = from, to = to, auto.assign = TRUE, warnings = FALSE)
    xts_data <- get(ticker)
  }, error = function(e) {
    cat("HATA: Veri cekilemedi:", conditionMessage(e), "\n"); return(NULL)
  })

  df <- data.frame(
    Date = as.character(index(xts_data)),
    Open = as.numeric(Op(xts_data)), High = as.numeric(Hi(xts_data)),
    Low = as.numeric(Lo(xts_data)), Close = as.numeric(Cl(xts_data)),
    Volume = as.numeric(Vo(xts_data)))
  df <- df[df$Volume > 0 & complete.cases(df[, c("Open","High","Low","Close")]), ]

  if (nrow(df) < 200) {
    cat(sprintf("YETERSIZ VERI: %d satir\n", nrow(df)))
    return(data.frame(ticker = ticker, n_data = nrow(df), error = "yetersiz_veri"))
  }

  df$RSI <- TTR::RSI(df$Close, n = 14)
  macd_v <- TTR::MACD(df$Close); df$MACD <- macd_v[, "macd"]
  df$EMA12 <- TTR::EMA(df$Close, n = 12); df$EMA26 <- TTR::EMA(df$Close, n = 26)
  stoch_v <- TTR::stoch(df[, c("High","Low","Close")])
  df$SO_K <- stoch_v[, "fastK"]; df$SO_D <- stoch_v[, "fastD"]
  adx_v <- TTR::ADX(df[, c("High","Low","Close")]); df$ADX <- adx_v[, "ADX"]
  df <- df[28:nrow(df), ] %>% drop_na()
  cat(sprintf("  Temiz veri: %d satir\n", nrow(df)))

  IN_LEN <- 2L; OUT_LEN <- 3L
  feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26","SO_K","SO_D","ADX")
  F_DIM <- length(feat_cols)
  feats <- as.matrix(df[, feat_cols])
  prices <- df$Close; N <- nrow(feats)

  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN + 1):(N - OUT_LEN)) {
    X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
    y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec; n_total <- length(y_arr)

  i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
  X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr + OUT_LEN):i_va, , , drop = FALSE]
  y_va <- y_arr[(i_tr + OUT_LEN):i_va]
  X_te <- X_arr[(i_va + OUT_LEN):n_total, , , drop = FALSE]
  y_te <- y_arr[(i_va + OUT_LEN):n_total]
  mu_a <- apply(X_tr, c(2,3), mean)
  sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  X_tr_n <- sweep(sweep(X_tr, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_va_n <- sweep(sweep(X_va, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_te_n <- sweep(sweep(X_te, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1); nt <- length(y_tr)
  cw <- list("0" = nt / (2 * n0), "1" = nt / (2 * n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  cat(sprintf("  Split: Tr=%d Va=%d Te=%d | Up%%: Tr=%.1f Te=%.1f | Naive=%.3f\n",
              length(y_tr), length(y_va), length(y_te),
              100 * mean(y_tr), 100 * mean(y_te), naive_acc))

  results <- list()
  for (sd_v in SEEDS) {
    keras3::clear_session()
    gc()
    set_full_seed(sd_v)
    tryCatch({
      # Glorot init explicit seed ile
      init_glorot <- keras3::initializer_glorot_uniform(seed = sd_v)
      inner <- keras3::layer_lstm(units = 64, activation = "tanh",
                                   return_sequences = FALSE,
                                   kernel_initializer = init_glorot,
                                   recurrent_initializer = init_glorot)
      model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
      model <- bidir_fn(model, inner, merge_mode = "concat")
      model <- model %>%
        keras3::layer_dropout(rate = 0.4) %>%
        keras3::layer_dense(units = 1, activation = "sigmoid",
                            kernel_initializer = init_glorot)
      model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
                                loss = make_mc_loss(0.05),
                                metrics = c("accuracy"))
      # GEVSETILMIS erken durdurma: patience 10, min_delta 0.005
      cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                             patience = 10L,
                                             min_delta = 0.005,
                                             restore_best_weights = TRUE)
      hist_ <- model %>% keras3::fit(X_tr_n, y_tr,
                                      validation_data = list(X_va_n, y_va),
                                      epochs = 100L, batch_size = 32L,
                                      verbose = 0L, callbacks = list(cb),
                                      class_weight = cw)
      yhat <- as.numeric(predict(model, X_te_n, verbose = 0L))
      m <- compute_metrics(y_te, yhat, 0.5)
      n_epoch_trained <- length(hist_$metrics$loss)

      cat(sprintf("  [DL] seed=%d: Acc=%.3f flip=%.3f naive=%.3f flip_beats=%s MC=%s epoch=%d\n",
                  sd_v, m$Acc, m$Acc_flip, naive_acc,
                  m$Acc_flip > naive_acc, m$is_MC, n_epoch_trained))

      results[[length(results) + 1]] <- data.frame(
        ticker = ticker, model = "BiLSTM_v2", seed = sd_v,
        acc = m$Acc, acc_flip = m$Acc_flip,
        sens = m$Sens, spec = m$Spec,
        naive_acc = naive_acc,
        n_epoch_trained = n_epoch_trained,
        flip_beats = m$Acc_flip > naive_acc,
        strict_anti_pred = (m$Acc_flip > naive_acc) & (m$Acc <= naive_acc),
        is_MC = m$is_MC, stringsAsFactors = FALSE)
    }, error = function(e) {
      cat("  seed=", sd_v, " HATA:", conditionMessage(e), "\n")
    })
  }
  do.call(rbind, results)
}

# --- Ana ---
TICKERS <- c("TURSG.IS", "AKGRT.IS", "ANSGR.IS", "RAYSG.IS", "AGESA.IS")
all_results <- list()
for (tk in TICKERS) {
  res <- test_stock_v2(tk)
  if (!is.null(res) && nrow(res) > 0) all_results[[length(all_results) + 1]] <- res
}

if (length(all_results) > 0) {
  all_df <- do.call(rbind, all_results)
  if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE)
  write.csv(all_df, file.path(OUTDIR, "mcaware_bist5_sigorta_v2_RESULTS.csv"), row.names = FALSE)

  # Seed varyansi
  seed_var <- all_df %>%
    group_by(ticker) %>%
    summarise(n_seeds = n(),
              acc_mean = mean(acc), acc_std = sd(acc),
              acc_min = min(acc), acc_max = max(acc),
              acc_n_unique = length(unique(round(acc, 6))),
              .groups = "drop")
  cat("\n=== SEED VARYANS ANALIZI (v2) ===\n")
  print(seed_var)

  # Siki kriter ozet
  summary_df <- all_df %>%
    group_by(ticker) %>%
    summarise(n_seeds = n(),
              mean_acc = mean(acc),
              mean_flip = mean(acc_flip),
              naive = mean(naive_acc),
              flip_beats_n = sum(flip_beats),
              strict_anti_pred_n = sum(strict_anti_pred),
              avg_epoch_trained = mean(n_epoch_trained),
              .groups = "drop") %>%
    mutate(siki_anti_pred = strict_anti_pred_n >= ceiling(n_seeds * 0.6))
  cat("\n=== SIGORTA v2 OZET (SIKI KRITER) ===\n")
  print(summary_df)

  write.csv(summary_df, file.path(OUTDIR, "mcaware_bist5_sigorta_v2_SUMMARY.csv"), row.names = FALSE)
  write.csv(seed_var, file.path(OUTDIR, "mcaware_bist5_sigorta_v2_SEED_VAR.csv"), row.names = FALSE)
  cat("\nDosyalar Sonuclar/ klasorune kaydedildi.\n")
}
cat("\nBIST-5 SIGORTA v2 TAMAMLANDI.\n")

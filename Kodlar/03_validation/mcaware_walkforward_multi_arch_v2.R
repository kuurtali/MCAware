# ===========================================================================
# MC-AWARE — WALK-FORWARD CV x 6 MIMARI v2 (DUZELTILMIS VERSIYON)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Olusturulma: 03 Haziran 2026
# ---------------------------------------------------------------------------
# DEGISIKLIKLER (v1 -> v2):
#   1. OUT_LEN = 1 -> 3 (referans pipeline ile ayni)
#   2. from = "2014-01-01" -> "2018-01-01" (referans ile ayni)
#   3. Fear.Greed = 50 (olu feature) -> gercek TCMB_Rate (FRED'den)
#   4. validation_data EKLENDI (v1'de YOKTU!)
#   5. monitor = "accuracy" (train) -> "val_accuracy" (validation)
#   6. Seed sayisi: 1 -> 3 (robustluk icin)
#   7. Epochs: 30 -> 50 (referans ile ayni)
#   8. Lambda: 0.05 sabit -> 0 (saf BCE, referans ile tutarli)
#   9. Cikti dosyalari _v2 suffix ile (eski CSV'lere dokunulmaz)
#
# AMACI:
#   Walk-forward CV'de 7 fold x 6 mimari x 3 seed = 126 kosu.
#   "Mimari-bagimsiz anti-prediktivite" iddiasini proper validation ile test et.
#
# MIMARILER: BiLSTM, GRU, SimpleRNN, Conv1D, TCN, Transformer
# VARLIK: THYAO
# CIKTI: Sonuclar/summaries/mcaware_walkforward_multi_arch_v2_*.csv
# Sure: ~3-4 saat (CPU)
# ===========================================================================

if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)

WORKDIR <- here::here()
OUTDIR_SUM <- here::here("Sonuclar", "summaries")
if (!dir.exists(OUTDIR_SUM)) dir.create(OUTDIR_SUM, recursive = TRUE)

setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse); library(TTR); library(zoo)
  library(keras3); library(tensorflow); library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE — WALK-FORWARD CV x 6 MIMARI v2 (DUZELTILMIS)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Degisiklikler: OUT_LEN=3, val_data EKLENDI, TCMB gercek, 3 seed\n")
cat("========================================================================\n\n")

# --- Yardimcilar ---
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

# Mimari fabrikasi
build_model <- function(arch, IN_LEN, F_DIM, seed = 23) {
  keras3::set_random_seed(seed)
  if (arch == "BiLSTM") {
    inner <- keras3::layer_lstm(units = 64, activation = "tanh",
                                return_sequences = FALSE)
    m <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
    .ns <- asNamespace("keras3")
    bidir_fn <- if (exists("bidirectional", envir = .ns)) get("bidirectional", envir = .ns) else get("layer_bidirectional", envir = .ns)
    m <- bidir_fn(m, inner, merge_mode = "concat")
    m <- m %>% keras3::layer_dropout(rate = 0.4) %>%
      keras3::layer_dense(units = 1, activation = "sigmoid")
  } else if (arch == "GRU") {
    m <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
      keras3::layer_gru(units = 64, activation = "tanh") %>%
      keras3::layer_dropout(rate = 0.4) %>%
      keras3::layer_dense(units = 1, activation = "sigmoid")
  } else if (arch == "SimpleRNN") {
    m <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
      keras3::layer_simple_rnn(units = 64, activation = "tanh") %>%
      keras3::layer_dropout(rate = 0.4) %>%
      keras3::layer_dense(units = 1, activation = "sigmoid")
  } else if (arch == "Conv1D") {
    m <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
      keras3::layer_conv_1d(filters = 64, kernel_size = 2,
                            activation = "relu", padding = "causal") %>%
      keras3::layer_global_average_pooling_1d() %>%
      keras3::layer_dropout(rate = 0.4) %>%
      keras3::layer_dense(units = 1, activation = "sigmoid")
  } else if (arch == "TCN") {
    inp <- keras3::layer_input(shape = c(IN_LEN, F_DIM))
    x <- inp %>%
      keras3::layer_conv_1d(filters = 64, kernel_size = 2,
                            dilation_rate = 1, padding = "causal",
                            activation = "relu")
    x <- x %>%
      keras3::layer_conv_1d(filters = 64, kernel_size = 2,
                            dilation_rate = 2, padding = "causal",
                            activation = "relu")
    x <- x %>% keras3::layer_global_average_pooling_1d() %>%
      keras3::layer_dropout(rate = 0.4) %>%
      keras3::layer_dense(units = 1, activation = "sigmoid")
    m <- keras3::keras_model(inp, x)
  } else if (arch == "Transformer") {
    inp <- keras3::layer_input(shape = c(IN_LEN, F_DIM))
    attn <- keras3::layer_multi_head_attention(num_heads = 4, key_dim = 32)
    a <- attn(inp, inp, inp)
    a <- keras3::layer_layer_normalization()(keras3::layer_add(list(inp, a)))
    a <- a %>% keras3::layer_global_average_pooling_1d() %>%
      keras3::layer_dropout(rate = 0.4) %>%
      keras3::layer_dense(units = 1, activation = "sigmoid")
    m <- keras3::keras_model(inp, a)
  } else stop("Bilinmeyen arch: ", arch)
  m
}

compute_metrics <- function(y_true, yhat, threshold = 0.5) {
  pred <- as.integer(yhat > threshold)
  acc <- mean(pred == y_true)
  list(Acc = acc, Acc_flip = 1 - acc,
       Sens = if (sum(y_true == 1) > 0) sum(pred == 1 & y_true == 1) / sum(y_true == 1) else NA,
       Spec = if (sum(y_true == 0) > 0) sum(pred == 0 & y_true == 0) / sum(y_true == 0) else NA,
       is_MC = isTRUE(sum(pred == 1) == 0) || isTRUE(sum(pred == 0) == 0))
}

# --- Veri (THYAO + gercek makro, from=2018) ---
cat("Veri cekiliyor: THYAO.IS + USDTRY + Oil + TCMB (2018-2026)\n")
getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
thy <- THYAO.IS

df <- data.frame(Date = as.character(index(thy)),
                 Open = as.numeric(Op(thy)), High = as.numeric(Hi(thy)),
                 Low = as.numeric(Lo(thy)), Close = as.numeric(Cl(thy)),
                 Volume = as.numeric(Vo(thy)))
df <- df[df$Volume > 0 & complete.cases(df[, c("Open","High","Low","Close")]), ]

# Makro degiskenler (gercek veri)
tryCatch({
  getSymbols("USDTRY=X", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  usdtry_df <- data.frame(Date = as.character(index(`USDTRY=X`)),
                           USDTRY = as.numeric(Cl(`USDTRY=X`)))
}, error = function(e) {
  usdtry_df <<- data.frame(Date = character(0), USDTRY = numeric(0))
})

tryCatch({
  getSymbols("CL=F", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  oil_df <- data.frame(Date = as.character(index(`CL=F`)),
                        Oil = as.numeric(Cl(`CL=F`)))
}, error = function(e) {
  oil_df <<- data.frame(Date = character(0), Oil = numeric(0))
})

tryCatch({
  getSymbols("INTDSRTRM193N", src = "FRED", from = "2018-01-01",
             to = "2026-03-31", auto.assign = TRUE, warnings = FALSE)
  tcmb_df <- data.frame(Date = as.Date(index(INTDSRTRM193N)),
                          TCMB_Rate = as.numeric(INTDSRTRM193N))
  tcmb_daily <- data.frame(Date = as.Date(df$Date)) %>%
    mutate(YearMonth = format(Date, "%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth = format(Date, "%Y-%m")),
              by = "YearMonth") %>%
    select(Date = Date.x, TCMB_Rate)
}, error = function(e) {
  tcmb_daily <<- data.frame(Date = as.Date(df$Date), TCMB_Rate = NA_real_)
})

df <- df %>%
  left_join(usdtry_df, by = "Date") %>%
  left_join(oil_df, by = "Date") %>%
  left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")
df$USDTRY <- zoo::na.locf(df$USDTRY, na.rm = FALSE)
df$Oil <- zoo::na.locf(df$Oil, na.rm = FALSE)
df$TCMB_Rate <- zoo::na.locf(df$TCMB_Rate, na.rm = FALSE)

# Teknik gostergeler
df$RSI <- TTR::RSI(df$Close, n = 14)
macd_v <- TTR::MACD(df$Close); df$MACD <- macd_v[, "macd"]
df$EMA12 <- TTR::EMA(df$Close, n = 12); df$EMA26 <- TTR::EMA(df$Close, n = 26)
stoch_v <- TTR::stoch(df[, c("High","Low","Close")])
df$SO_K <- stoch_v[, "fastK"]; df$SO_D <- stoch_v[, "fastD"]
adx_v <- TTR::ADX(df[, c("High","Low","Close")])
df$ADX <- adx_v[, "ADX"]
df <- df[28:nrow(df), ] %>% drop_na()
cat(sprintf("Temiz veri: %d satir\n", nrow(df)))

# --- Pencereleme ---
IN_LEN  <- 2L
OUT_LEN <- 3L  # v2 DUZELTME: 1 -> 3
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(df[, feat_cols])
prices <- df$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
n_total <- length(y_arr)
cat(sprintf("Toplam ornek: %d\n", n_total))

# --- Walk-forward parametreleri ---
TRAIN_ENDS <- c(500, 700, 900, 1100, 1300, 1500, 1700)
ARCHS  <- c("BiLSTM", "GRU", "SimpleRNN", "Conv1D", "TCN", "Transformer")
LAMBDA <- 0.0   # v2: saf BCE (referans ile tutarli)
SEEDS  <- c(23L, 42L, 98L)  # v2: 3 seed (v1'de sadece 1 vardi)

all_results <- list()

for (fold_i in seq_along(TRAIN_ENDS)) {
  tr_end <- TRAIN_ENDS[fold_i]
  test_start <- tr_end + 1; test_end <- tr_end + 200
  if (test_end > n_total) {
    cat(sprintf("Fold %d: yeterli test verisi yok (gerekli: %d, mevcut: %d)\n",
                fold_i, test_end, n_total))
    next
  }

  # v2 DUZELTME: Train'in son %15'i validation olarak ayrilir
  val_size <- floor(tr_end * 0.15)
  tr_actual_end <- tr_end - val_size

  X_tr <- X_arr[1:tr_actual_end, , , drop = FALSE]
  y_tr <- y_arr[1:tr_actual_end]
  X_va <- X_arr[(tr_actual_end + 1):tr_end, , , drop = FALSE]
  y_va <- y_arr[(tr_actual_end + 1):tr_end]
  X_te <- X_arr[test_start:test_end, , , drop = FALSE]
  y_te <- y_arr[test_start:test_end]

  # Normalize (train stats ile)
  mu_a <- apply(X_tr, c(2,3), mean)
  sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  norm_fn <- function(A) sweep(sweep(A, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_tr_n <- norm_fn(X_tr); X_va_n <- norm_fn(X_va); X_te_n <- norm_fn(X_te)

  n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1); nt <- length(y_tr)
  cw <- list("0" = nt / (2 * n0), "1" = nt / (2 * n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
  cat(sprintf("\nFold %d: train[1:%d] val[%d:%d] test[%d:%d] | Naive=%.3f\n",
              fold_i, tr_actual_end, tr_actual_end+1, tr_end, test_start, test_end, naive_acc))

  for (arch in ARCHS) {
    for (sd in SEEDS) {
      keras3::clear_session()
      tryCatch({
        model <- build_model(arch, IN_LEN, F_DIM, seed = sd)
        model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
                                  loss = make_mc_loss(LAMBDA),
                                  metrics = c("accuracy"))
        # v2 DUZELTME: validation_data EKLENDI, monitor = "val_accuracy"
        cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                               patience = 5L,
                                               restore_best_weights = TRUE)
        model %>% keras3::fit(X_tr_n, y_tr,
                              validation_data = list(X_va_n, y_va),
                              epochs = 50L, batch_size = 32L,
                              verbose = 0L, callbacks = list(cb),
                              class_weight = cw)
        yhat <- as.numeric(predict(model, X_te_n, verbose = 0L))
        m <- compute_metrics(y_te, yhat, 0.5)
        cat(sprintf("  %-12s sd=%d Acc=%.3f flip=%.3f %s\n",
                    arch, sd, m$Acc, m$Acc_flip,
                    if(m$Acc_flip > naive_acc) "FLIP>NAIVE" else ""))
        all_results[[length(all_results) + 1]] <- data.frame(
          fold = fold_i, arch = arch, seed = sd, naive = naive_acc,
          Acc = m$Acc, Acc_flip = m$Acc_flip,
          Sens = m$Sens, Spec = m$Spec, is_MC = m$is_MC,
          flip_beats_naive = m$Acc_flip > naive_acc,
          strict_anti_pred = (m$Acc_flip > naive_acc) & (m$Acc <= naive_acc)
        )
      }, error = function(e) {
        cat(sprintf("  %-12s sd=%d HATA: %s\n", arch, sd, conditionMessage(e)))
      })
    }
  }
}

all_df <- do.call(rbind, all_results)

# Mimari bazinda ozet
arch_summary <- all_df %>%
  group_by(arch) %>%
  summarise(n_total = n(),
            flip_beats_naive_n = sum(flip_beats_naive),
            strict_anti_pred_n = sum(strict_anti_pred),
            mc_n = sum(is_MC),
            mean_acc = mean(Acc),
            mean_flip = mean(Acc_flip),
            .groups = "drop")

# Fold bazinda ozet
fold_summary <- all_df %>%
  group_by(fold) %>%
  summarise(n_arch_seed = n(),
            flip_beats_naive_n = sum(flip_beats_naive),
            strict_anti_pred_n = sum(strict_anti_pred),
            mean_acc = mean(Acc),
            mean_flip = mean(Acc_flip),
            naive = mean(naive),
            .groups = "drop")

cat("\n=== MIMARI BAZINDA (v2) ===\n")
print(arch_summary)
cat("\n=== FOLD BAZINDA (v2) ===\n")
print(fold_summary)

# --- CSV kayit (_v2 suffix) ---
write.csv(all_df, file.path(OUTDIR_SUM, "mcaware_walkforward_multi_arch_v2_RESULTS.csv"),
          row.names = FALSE)
write.csv(arch_summary, file.path(OUTDIR_SUM, "mcaware_walkforward_multi_arch_v2_ARCH_SUMMARY.csv"),
          row.names = FALSE)
write.csv(fold_summary, file.path(OUTDIR_SUM, "mcaware_walkforward_multi_arch_v2_FOLD_SUMMARY.csv"),
          row.names = FALSE)

cat(sprintf("\nKaydedildi:\n  %s\n  %s\n  %s\n",
            file.path(OUTDIR_SUM, "mcaware_walkforward_multi_arch_v2_RESULTS.csv"),
            file.path(OUTDIR_SUM, "mcaware_walkforward_multi_arch_v2_ARCH_SUMMARY.csv"),
            file.path(OUTDIR_SUM, "mcaware_walkforward_multi_arch_v2_FOLD_SUMMARY.csv")))
cat("\nWALK-FORWARD MULTI-ARCH v2 TAMAMLANDI.\n")

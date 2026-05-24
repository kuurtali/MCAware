# ===========================================================================
# MC-AWARE — WALK-FORWARD CV × 6 MÝMARÝ (DENEY I.21)
# TUBITAK 2209-A — Yurutucu: Mehmet Ali KURT
# Olusturulma: 23 Mayis 2026 (v3 sonradan ek)
# ---------------------------------------------------------------------------
# AMACI:
#   "Mimari-bagimsiz anti-prediktivite" iddiasi tek-split kanitina dayaniyor.
#   Walk-forward sadece BiLSTM'de yapildi (3/7 fold flip>naive).
#   Bu deneyde 7 fold x 6 mimari = 42 koþu yapilir. Sonuc:
#     - Mimari-bagimsiz "donemsel anti-pred" gercekten gozleniyor mu?
#     - Hangi foldlar/mimariler tutarli?
#   beklenir.
#
# MIMARILER: BiLSTM, GRU, SimpleRNN, Conv1D, TCN, Transformer
# VARLIK: THYAO
# CIKTI: Sonuclar/summaries/mcaware_walkforward_multi_arch_*.csv
# Sure: ~2-3 saat (CPU)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- here::here()
OUTDIR  <- file.path(here::here("Sonuclar"), "summaries")
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(keras3)
  library(tensorflow)
  library(quantmod)
})

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
    # Basit dilated conv
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

# --- Veri (THYAO + makro) ---
cat("Veri cekiliyor: THYAO.IS + USDTRY=X + CL=F\n")
getSymbols("THYAO.IS", from = "2014-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
thy <- THYAO.IS
getSymbols("USDTRY=X", from = "2014-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
usd <- get("USDTRY=X")
getSymbols("CL=F", from = "2014-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
oil <- get("CL=F")
df <- data.frame(Date = as.character(index(thy)),
                 Open = as.numeric(Op(thy)), High = as.numeric(Hi(thy)),
                 Low = as.numeric(Lo(thy)), Close = as.numeric(Cl(thy)),
                 Volume = as.numeric(Vo(thy)))
df <- df[df$Volume > 0 & complete.cases(df[, c("Open","High","Low","Close")]), ]
df <- df %>%
  left_join(data.frame(Date = as.character(index(usd)),
                       USDTRY = as.numeric(Cl(usd))), by = "Date") %>%
  left_join(data.frame(Date = as.character(index(oil)),
                       Oil = as.numeric(Cl(oil))), by = "Date")
df$USDTRY <- zoo::na.locf(df$USDTRY, na.rm = FALSE)
df$Oil <- zoo::na.locf(df$Oil, na.rm = FALSE)
df$TCMB <- 15.0; df$Fear.Greed <- 50.0
df$RSI <- TTR::RSI(df$Close, n = 14)
macd_v <- TTR::MACD(df$Close); df$MACD <- macd_v[, "macd"]
df$EMA12 <- TTR::EMA(df$Close, n = 12); df$EMA26 <- TTR::EMA(df$Close, n = 26)
stoch_v <- TTR::stoch(df[, c("High","Low","Close")])
df$SO_K <- stoch_v[, "fastK"]; df$SO_D <- stoch_v[, "fastD"]
adx_v <- TTR::ADX(df[, c("High","Low","Close")])
df$ADX <- adx_v[, "ADX"]
df <- df[28:nrow(df), ] %>% drop_na()
cat(sprintf("Temiz veri: %d satir\n", nrow(df)))

IN_LEN <- 2L; OUT_LEN <- 1L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26","SO_K",
               "SO_D","ADX","USDTRY","Oil","Fear.Greed")
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

# Walk-forward foldlari (BiLSTM walk-forward'taki ile uyumlu)
TRAIN_ENDS <- c(500, 700, 900, 1100, 1300, 1500, 1700)
ARCHS <- c("BiLSTM", "GRU", "SimpleRNN", "Conv1D", "TCN", "Transformer")
LAMBDA <- 0.05
SEED <- 23L

all_results <- list()

for (fold_i in seq_along(TRAIN_ENDS)) {
  te_end <- TRAIN_ENDS[fold_i]
  test_start <- te_end + 1; test_end <- te_end + 200
  if (test_end > n_total) {
    cat(sprintf("Fold %d: yeterli test verisi yok\n", fold_i))
    next
  }
  X_tr <- X_arr[1:te_end, , , drop = FALSE]; y_tr <- y_arr[1:te_end]
  X_te <- X_arr[test_start:test_end, , , drop = FALSE]
  y_te <- y_arr[test_start:test_end]
  mu_a <- apply(X_tr, c(2,3), mean)
  sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  X_tr_n <- sweep(sweep(X_tr, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_te_n <- sweep(sweep(X_te, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1); nt <- length(y_tr)
  cw <- list("0" = nt / (2 * n0), "1" = nt / (2 * n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
  cat(sprintf("\nFold %d: train[1:%d] test[%d:%d] | Naive=%.3f\n",
              fold_i, te_end, test_start, test_end, naive_acc))

  for (arch in ARCHS) {
    keras3::clear_session()
    model <- build_model(arch, IN_LEN, F_DIM, seed = SEED)
    model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
                              loss = make_mc_loss(LAMBDA),
                              metrics = c("accuracy"))
    cb <- keras3::callback_early_stopping(monitor = "accuracy",
                                           patience = 5L,
                                           restore_best_weights = TRUE)
    model %>% keras3::fit(X_tr_n, y_tr,
                          epochs = 30L, batch_size = 32L,
                          verbose = 0L, callbacks = list(cb),
                          class_weight = cw)
    yhat <- as.numeric(predict(model, X_te_n, verbose = 0L))
    m <- compute_metrics(y_te, yhat, 0.5)
    cat(sprintf("  %-12s Acc=%.3f flip=%.3f flip>naive=%s MC=%s\n",
                arch, m$Acc, m$Acc_flip,
                m$Acc_flip > naive_acc, m$is_MC))
    all_results[[length(all_results) + 1]] <- data.frame(
      fold = fold_i, arch = arch, naive = naive_acc,
      Acc = m$Acc, Acc_flip = m$Acc_flip,
      Sens = m$Sens, Spec = m$Spec, is_MC = m$is_MC,
      flip_beats_naive = m$Acc_flip > naive_acc,
      strict_anti_pred = (m$Acc_flip > naive_acc) & (m$Acc <= naive_acc)
    )
  }
}

all_df <- do.call(rbind, all_results)

# Mimari bazinda ozet
arch_summary <- all_df %>%
  group_by(arch) %>%
  summarise(n_folds = n(),
            flip_beats_naive_n = sum(flip_beats_naive),
            strict_anti_pred_n = sum(strict_anti_pred),
            mc_n = sum(is_MC),
            mean_acc = mean(Acc),
            mean_flip = mean(Acc_flip),
            .groups = "drop")

# Fold bazinda ozet
fold_summary <- all_df %>%
  group_by(fold) %>%
  summarise(n_arch = n(),
            flip_beats_naive_n = sum(flip_beats_naive),
            strict_anti_pred_n = sum(strict_anti_pred),
            mean_acc = mean(Acc),
            mean_flip = mean(Acc_flip),
            naive = mean(naive),
            .groups = "drop")

cat("\n=== MIMARI BAZINDA ===\n")
print(arch_summary)
cat("\n=== FOLD BAZINDA ===\n")
print(fold_summary)

if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE)
write.csv(all_df, file.path(OUTDIR, "mcaware_walkforward_multi_arch_RESULTS.csv"),
          row.names = FALSE)
write.csv(arch_summary, file.path(OUTDIR, "mcaware_walkforward_multi_arch_ARCH_SUMMARY.csv"),
          row.names = FALSE)
write.csv(fold_summary, file.path(OUTDIR, "mcaware_walkforward_multi_arch_FOLD_SUMMARY.csv"),
          row.names = FALSE)
cat("\nWALK-FORWARD MULTI-ARCH TAMAMLANDI.\n")

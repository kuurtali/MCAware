# ===========================================================================
# MC-AWARE — IN_LEN ABLASYONU v2 (DUZELTILMIS VERSIYON)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Olusturulma: 03 Haziran 2026
# ---------------------------------------------------------------------------
# DEGISIKLIKLER (v1 -> v2):
#   1. OUT_LEN = 1 -> 3 (referans pipeline ile ayni)
#   2. from = "2014-01-01" -> "2018-01-01" (referans ile ayni)
#   3. Fear.Greed = 50 (olu feature) -> gercek TCMB_Rate (FRED'den)
#   4. Val/Train split gap duzeltildi: (i_tr+OUT_LEN) -> (i_tr+1L)
#   5. Cikti dosyalari _v2 suffix ile (eski CSV'lere dokunulmaz)
#
# AMACI:
#   "Anti-prediktif davranis pencere uzunluguna bagli mi?" sorusunu test et.
#   IN_LEN = {2, 5, 10} ile kosturup:
#     - MC tuzagi cozumu hala calisiyor mu?
#     - Flip>naive orani benzer mi?
#     - Acc dagilimi nasil degisiyor?
#
# MIMARI: BiLSTM v3b (ana mimari, referans)
# VARLIK: THYAO
# CIKTI: Sonuclar/summaries/mcaware_inlen_ablation_v2_*.csv
# Sure: ~30 dk (3 IN_LEN x 3 lambda x 5 seed = 45 kosu)
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
cat("MC-AWARE — IN_LEN ABLASYONU v2 (DUZELTILMIS)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Degisiklikler: OUT_LEN=3, from=2018, gercek TCMB_Rate\n")
cat("========================================================================\n\n")

.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) {
      bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    } else bce
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
  list(Acc = acc, Sens = sens, Spec = spec, is_MC = is_mc, Acc_flip = 1 - acc)
}

# --- THYAO veri (from = 2018, referans ile ayni) ---
cat("Veri cekiliyor: THYAO.IS (2018-2026)\n")
getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
thy <- THYAO.IS
df <- data.frame(
  Date = as.character(index(thy)),
  Open = as.numeric(Op(thy)), High = as.numeric(Hi(thy)),
  Low = as.numeric(Lo(thy)), Close = as.numeric(Cl(thy)),
  Volume = as.numeric(Vo(thy))
)
df <- df[df$Volume > 0 & complete.cases(df[, c("Open","High","Low","Close")]), ]

# --- Makro degiskenler (gercek veri, placeholder DEGIL) ---
cat("Dis degiskenler cekiliyor (USDTRY, Oil, TCMB)...\n")
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

df_final <- df %>%
  left_join(usdtry_df, by = "Date") %>%
  left_join(oil_df, by = "Date") %>%
  left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")

df_final$USDTRY <- zoo::na.locf(df_final$USDTRY, na.rm = FALSE)
df_final$Oil <- zoo::na.locf(df_final$Oil, na.rm = FALSE)
df_final$TCMB_Rate <- zoo::na.locf(df_final$TCMB_Rate, na.rm = FALSE)

# Teknik gostergeler
df_final$RSI <- TTR::RSI(df_final$Close, n = 14)
macd_v <- TTR::MACD(df_final$Close); df_final$MACD <- macd_v[, "macd"]
df_final$EMA12 <- TTR::EMA(df_final$Close, n = 12)
df_final$EMA26 <- TTR::EMA(df_final$Close, n = 26)
stoch_v <- TTR::stoch(df_final[, c("High","Low","Close")])
df_final$SO_K <- stoch_v[, "fastK"]; df_final$SO_D <- stoch_v[, "fastD"]
adx_v <- TTR::ADX(df_final[, c("High","Low","Close")])
df_final$ADX <- adx_v[, "ADX"]

df_final <- df_final[28:nrow(df_final), ] %>% drop_na()
cat(sprintf("Temiz veri: %d satir\n", nrow(df_final)))

# --- Feature seti (referans pipeline ile AYNI: 13 boyut) ---
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(df_final[, feat_cols])
prices <- df_final$Close
N <- nrow(feats)

cat(sprintf("Feature boyutu: %d (USDTRY + Oil + TCMB_Rate dahil)\n", F_DIM))

# --- IN_LEN sweep ---
IN_LENS <- c(2L, 5L, 10L)
LAMBDAS <- c(0.0, 0.05, 0.10)
SEEDS   <- c(23L, 27L, 98L, 41L, 64L)
OUT_LEN <- 3L  # v2 DUZELTME: 1 -> 3 (referans ile ayni)

all_results <- list()

for (IN_LEN in IN_LENS) {
  cat(sprintf("\n%s\nIN_LEN = %d (OUT_LEN = %d)\n%s\n",
              strrep("=", 60), IN_LEN, OUT_LEN, strrep("=", 60)))

  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN + 1):(N - OUT_LEN)) {
    X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
    y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec; n_total <- length(y_arr)

  # Split (v2 DUZELTME: gap yok, referans ile ayni)
  i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
  X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr + 1L):i_va, , , drop = FALSE]
  y_va <- y_arr[(i_tr + 1L):i_va]
  X_te <- X_arr[(i_va + 1L):n_total, , , drop = FALSE]
  y_te <- y_arr[(i_va + 1L):n_total]

  # Normalize (train stats ile)
  mu_a <- apply(X_tr, c(2,3), mean)
  sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  X_tr_n <- sweep(sweep(X_tr, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_va_n <- sweep(sweep(X_va, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_te_n <- sweep(sweep(X_te, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")

  n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1); nt <- length(y_tr)
  cw <- list("0" = nt / (2 * n0), "1" = nt / (2 * n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
  cat(sprintf("  Split: Tr=%d Va=%d Te=%d | Naive=%.3f\n",
              length(y_tr), length(y_va), length(y_te), naive_acc))

  for (lam in LAMBDAS) {
    for (sd in SEEDS) {
      keras3::clear_session()
      keras3::set_random_seed(sd)
      inner <- keras3::layer_lstm(units = 64, activation = "tanh",
                                  return_sequences = FALSE)
      model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
      model <- bidir_fn(model, inner, merge_mode = "concat")
      model <- model %>%
        keras3::layer_dropout(rate = 0.4) %>%
        keras3::layer_dense(units = 1, activation = "sigmoid")
      model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
                                loss = make_mc_loss(lam),
                                metrics = c("accuracy"))
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
      cat(sprintf("  IN=%d lam=%.2f sd=%d: Acc=%.3f flip=%.3f naive=%.3f %s\n",
                  IN_LEN, lam, sd, m$Acc, m$Acc_flip, naive_acc,
                  if(m$Acc_flip > naive_acc) "FLIP>NAIVE" else ""))
      all_results[[length(all_results) + 1]] <- data.frame(
        IN_LEN = IN_LEN, lambda = lam, seed = sd,
        Acc = m$Acc, Acc_flip = m$Acc_flip,
        Sens = ifelse(is.null(m$Sens), NA_real_, m$Sens),
        Spec = ifelse(is.null(m$Spec), NA_real_, m$Spec),
        is_MC = m$is_MC,
        naive = naive_acc,
        flip_beats_naive = m$Acc_flip > naive_acc,
        strict_anti_pred = (m$Acc_flip > naive_acc) & (m$Acc <= naive_acc)
      )
    }
  }
}

all_df <- do.call(rbind, all_results)

# Ozet
summary_df <- all_df %>%
  group_by(IN_LEN) %>%
  summarise(n = n(),
            naive = mean(naive),
            mean_acc = mean(Acc),
            mean_flip = mean(Acc_flip),
            flip_beats_naive_n = sum(flip_beats_naive),
            strict_anti_pred_n = sum(strict_anti_pred),
            mc_n = sum(is_MC),
            .groups = "drop")

cat("\n=== IN_LEN ABLASYONU v2 SONUCLARI ===\n")
print(summary_df)

# --- CSV kayit (_v2 suffix) ---
write.csv(all_df, file.path(OUTDIR_SUM, "mcaware_inlen_ablation_v2_RESULTS.csv"),
          row.names = FALSE)
write.csv(summary_df, file.path(OUTDIR_SUM, "mcaware_inlen_ablation_v2_SUMMARY.csv"),
          row.names = FALSE)

cat(sprintf("\nKaydedildi:\n  %s\n  %s\n",
            file.path(OUTDIR_SUM, "mcaware_inlen_ablation_v2_RESULTS.csv"),
            file.path(OUTDIR_SUM, "mcaware_inlen_ablation_v2_SUMMARY.csv")))
cat("\nIN_LEN ABLASYONU v2 TAMAMLANDI.\n")

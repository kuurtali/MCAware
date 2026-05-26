# ===========================================================================
# MC-AWARE PROTOTYPE — MULTI-ARCHITECTURE v4 (ADIM I.8: MIMARI ABLATION)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   BiLSTM'de 45/45 anti-prediktif gozlem THYAO-spesifik ve CW-bagimsiz.
#   Soru: Bu BILSTM'e mi ozgu yoksa VERI OZELLIGI mi?
#   Test: 5 mimari ayni veri/pencere/grid ile kosturulur:
#     SimpleRNN, GRU, Conv1D, TCN (dilated causal), Transformer (MHA)
#   Eger hepsi anti-prediktif → VERI ozelligi (Yorum 3 cok guclenir)
#   Eger sadece BiLSTM → mimari artefakt (Yorum 3 zayiflar)
#   + McNemar testi: mimari cifleri arasinda istatistiksel fark
#
# KARAR MATRISI:
#   [A] >=4/5 mimari anti-prediktif → VERI OZELLIGI
#   [B] <=2/5 mimari anti-prediktif → MIMARIYE BAGLI artefakt
#   [C] Karisik → Heterojen
#
# CIKTI: 5 mimari x 4 CSV = 20 CSV + CROSS_ARCH_SUMMARY + McNEMAR
# Calistirma: RStudio → Ctrl+Shift+S → ~90-120 dk → 22 CSV
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
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse); library(TTR); library(zoo)
  library(keras3); library(tensorflow); library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — MULTI-ARCHITECTURE v4 (ADIM I.8)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Mimariler: SimpleRNN, GRU, Conv1D, TCN, Transformer\n")
cat("Referans: BiLSTM v3b (Acc=0.396, flip=0.604, 15/15)\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { warning("OUTDIR yok, WORKDIR kullaniliyor"); OUTDIR <- WORKDIR }

# --- 1. THYAO veri cekme (v3b/v3c ile AYNI) ---
cat("THYAO verisi cekiliyor...\n")
getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
thyao_xts <- THYAO.IS
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
stoch_vals     <- TTR::stoch(thyao_df[, c("High", "Low", "Close")])
thyao_df$SO_K  <- stoch_vals[, "fastK"]
thyao_df$SO_D  <- stoch_vals[, "fastD"]
adx_vals       <- TTR::ADX(thyao_df[, c("High", "Low", "Close")])
thyao_df$ADX   <- adx_vals[, "ADX"]

tryCatch({
  getSymbols("USDTRY=X", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  usdtry_df <- data.frame(Date=as.character(index(`USDTRY=X`)), USDTRY=as.numeric(Cl(`USDTRY=X`)))
}, error=function(e) { usdtry_df <<- data.frame(Date=character(0), USDTRY=numeric(0)) })
tryCatch({
  getSymbols("CL=F", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  oil_df <- data.frame(Date=as.character(index(`CL=F`)), Oil=as.numeric(Cl(`CL=F`)))
}, error=function(e) { oil_df <<- data.frame(Date=character(0), Oil=numeric(0)) })
tryCatch({
  getSymbols("INTDSRTRM193N", src="FRED", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  tcmb_df <- data.frame(Date=as.Date(index(INTDSRTRM193N)), TCMB_Rate=as.numeric(INTDSRTRM193N))
  tcmb_daily <- data.frame(Date=as.Date(thyao_df$Date)) %>%
    mutate(YearMonth=format(Date,"%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth=format(Date,"%Y-%m")), by="YearMonth") %>%
    select(Date=Date.x, TCMB_Rate)
}, error=function(e) { tcmb_daily <<- data.frame(Date=as.Date(thyao_df$Date), TCMB_Rate=NA_real_) })

thyao_final <- thyao_df %>%
  left_join(usdtry_df, by="Date") %>% left_join(oil_df, by="Date") %>%
  left_join(tcmb_daily %>% mutate(Date=as.character(Date)), by="Date")
thyao_final$USDTRY    <- zoo::na.locf(thyao_final$USDTRY, na.rm=FALSE)
thyao_final$Oil       <- zoo::na.locf(thyao_final$Oil, na.rm=FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm=FALSE)
thyao_final <- thyao_final[28:nrow(thyao_final), ] %>% drop_na()
cat(sprintf("Final THYAO: %d satir\n", nrow(thyao_final)))

# --- 2. Pencereleme (v3b ile AYNI - duzeltilmis) ---
IN_LEN <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec

# --- 3. Split ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr+1L):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
X_te <- X_arr[(i_va+1L):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+1L):n_total]
cat(sprintf("Split: Train=%d Val=%d Test=%d\n", length(y_tr), length(y_va), length(y_te)))

naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
cat(sprintf("NAIVE BASELINE: %.4f\n\n", naive_acc))

# --- 4. Normalize ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 5. Loss ---
make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) {
      bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    } else { bce }
  }
}

# --- 6. MODEL BUILDERS (BU SCRIPTIN KALBI — 5 MIMARI) ---

build_simple_rnn <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_simple_rnn(units = 64, activation = "tanh", return_sequences = FALSE) %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_gru <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_gru(units = 64, activation = "tanh", return_sequences = TRUE) %>%
    keras3::layer_gru(units = 32, activation = "tanh", return_sequences = FALSE) %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_conv1d <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_conv_1d(filters = 64, kernel_size = 1, activation = "relu",
                          padding = "same") %>%
    keras3::layer_conv_1d(filters = 32, kernel_size = 1, activation = "relu",
                          padding = "same") %>%
    keras3::layer_global_average_pooling_1d() %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_tcn <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  # TCN = dilated causal convolutions (IN_LEN=2 icin dilation=1 yeterli)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_conv_1d(filters = 64, kernel_size = 2, activation = "relu",
                          padding = "causal", dilation_rate = 1) %>%
    keras3::layer_conv_1d(filters = 32, kernel_size = 1, activation = "relu",
                          padding = "causal") %>%
    keras3::layer_global_average_pooling_1d() %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_transformer <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  # Functional API: Input -> MultiHeadAttention -> Dense
  inp <- keras3::layer_input(shape = c(IN_LEN, F_DIM))
  # Positional bilgi icin Dense projection
  x <- inp %>% keras3::layer_dense(units = 64, activation = "relu")
  # Self-attention
  attn_out <- keras3::layer_multi_head_attention(
    num_heads = 2, key_dim = 32)(x, x)
  x <- keras3::layer_add(list(x, attn_out))  # residual
  x <- keras3::layer_layer_normalization()(x)
  x <- keras3::layer_global_average_pooling_1d()(x)
  x <- keras3::layer_dropout(rate = 0.4)(x)
  out <- keras3::layer_dense(units = 1, activation = "sigmoid")(x)
  model <- keras3::keras_model(inputs = inp, outputs = out)
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

ARCH_BUILDERS <- list(
  SimpleRNN   = build_simple_rnn,
  GRU         = build_gru,
  Conv1D      = build_conv1d,
  TCN         = build_tcn,
  Transformer = build_transformer
)

# --- 7. Metrik ---
compute_metrics <- function(y_true, yhat, threshold) {
  pred <- as.integer(yhat > threshold)
  tp <- sum(pred==1 & y_true==1); tn <- sum(pred==0 & y_true==0)
  fp <- sum(pred==1 & y_true==0); fn <- sum(pred==0 & y_true==1)
  n <- length(y_true); acc <- (tp+tn)/n
  sens <- if ((tp+fn)>0) tp/(tp+fn) else NA_real_
  spec <- if ((tn+fp)>0) tn/(tn+fp) else NA_real_
  prec_ <- if ((tp+fp)>0) tp/(tp+fp) else NA_real_
  f1 <- if (!is.na(prec_)&&!is.na(sens)&&(prec_+sens)>0) 2*prec_*sens/(prec_+sens) else NA_real_
  bacc <- if (!is.na(sens)&&!is.na(spec)) (sens+spec)/2 else NA_real_
  is_mc <- isTRUE(spec==0)||isTRUE(sens==0)||is.na(spec)||is.na(sens)
  list(Acc=acc, Sens=sens, Spec=spec, Prec=prec_, F1=f1,
       BalAcc=bacc, is_MC=is_mc, Acc_flip=1-acc)
}

# --- 8. Train + predict ---
train_and_predict <- function(builder_fn, seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- builder_fn(seed, lambda_mc)
    # CW=balanced (v3b ile ayni)
    n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1); nt <- length(y_tr)
    w0 <- nt / (2 * n0); w1 <- nt / (2 * n1)
    cw <- list("0" = w0, "1" = w1)
    cb <- keras3::callback_early_stopping(monitor="val_accuracy",
                                           patience=5L, restore_best_weights=TRUE)
    model %>% keras3::fit(X_tr, y_tr, validation_data=list(X_va, y_va),
                          epochs=50L, batch_size=32L, verbose=0L,
                          callbacks=list(cb), class_weight=cw)
    yhat_val  <- as.numeric(predict(model, X_va, verbose=0L))
    yhat_test <- as.numeric(predict(model, X_te, verbose=0L))
    list(yhat_val=yhat_val, yhat_test=yhat_test, error=NA_character_)
  }, error=function(e) {
    list(yhat_val=rep(NA_real_, length(y_va)),
         yhat_test=rep(NA_real_, length(y_te)), error=conditionMessage(e))
  })
}

# --- 9. Grid ---
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cross_arch_rows <- list()

for (arch_name in names(ARCH_BUILDERS)) {
  builder_fn <- ARCH_BUILDERS[[arch_name]]
  cat(sprintf("\n%s\n", strrep("=", 95)))
  cat(sprintf("MIMARI: %s | %d lambda x %d seed = %d kosu\n",
              arch_name, length(LAMBDAS), length(SEEDS), length(LAMBDAS)*length(SEEDS)))
  cat(sprintf("%s\n", strrep("=", 95)))

  predictions_list <- list(); threshold_rows <- list()
  optimal_rows <- list(); yhat_stats_rows <- list()

  t0 <- Sys.time()
  for (lam in LAMBDAS) {
    for (sd_seed in SEEDS) {
      cat(sprintf("\n[%s] lambda=%.2f seed=%d ...\n", arch_name, lam, sd_seed))
      pred <- train_and_predict(builder_fn, sd_seed, lam)
      if (!is.na(pred$error)) { cat(" HATA:", pred$error, "\n"); next }

      yhat_stats_rows[[length(yhat_stats_rows)+1]] <- data.frame(
        arch=arch_name, lambda=lam, seed=sd_seed,
        test_min=min(pred$yhat_test), test_max=max(pred$yhat_test),
        test_mean=mean(pred$yhat_test), test_range=max(pred$yhat_test)-min(pred$yhat_test),
        stringsAsFactors=FALSE)

      for (i in seq_along(y_te)) {
        predictions_list[[length(predictions_list)+1]] <- data.frame(
          arch=arch_name, lambda=lam, seed=sd_seed, set="test",
          sample_id=i, yhat=pred$yhat_test[i], y_true=y_te[i], stringsAsFactors=FALSE)
      }
      for (thr in THRESHOLDS) {
        m_test <- compute_metrics(y_te, pred$yhat_test, thr)
        threshold_rows[[length(threshold_rows)+1]] <- data.frame(
          arch=arch_name, lambda=lam, seed=sd_seed, threshold=thr,
          Acc=m_test$Acc, Spec=m_test$Spec, Sens=m_test$Sens,
          BalAcc=m_test$BalAcc, Acc_flip=m_test$Acc_flip,
          is_MC=m_test$is_MC, stringsAsFactors=FALSE)
      }

      val_bacc <- sapply(THRESHOLDS, function(thr) {
        m <- compute_metrics(y_va, pred$yhat_val, thr)
        if (is.na(m$BalAcc)) -Inf else m$BalAcc })
      best_thr <- THRESHOLDS[which.max(val_bacc)]
      m05 <- compute_metrics(y_te, pred$yhat_test, 0.5)

      optimal_rows[[length(optimal_rows)+1]] <- data.frame(
        arch=arch_name, lambda=lam, seed=sd_seed, best_thr=best_thr,
        test_Acc_05=m05$Acc, test_Spec_05=m05$Spec, test_Sens_05=m05$Sens,
        test_Acc_flip_05=m05$Acc_flip,
        test_flip_beats_naive=m05$Acc_flip > naive_acc,
        test_is_MC_05=m05$is_MC, stringsAsFactors=FALSE)

      cat(sprintf("  yhat: min=%.3f max=%.3f | Acc=%.3f flip=%.3f MC=%s\n",
                  min(pred$yhat_test), max(pred$yhat_test),
                  m05$Acc, m05$Acc_flip, if(m05$is_MC) "YES" else "no"))
    }
  }
  t1 <- Sys.time()
  cat(sprintf("\n[%s] Sure: %.1f dk\n", arch_name, as.numeric(difftime(t1,t0,units="mins"))))

  # CSV kaydet
  pred_df <- do.call(rbind, predictions_list)
  thr_df  <- do.call(rbind, threshold_rows)
  opt_df  <- do.call(rbind, optimal_rows)
  yhat_df <- do.call(rbind, yhat_stats_rows)

  prefix <- paste0("mcaware_multi_arch_", arch_name, "_")
  write.csv(pred_df, file.path(OUTDIR_PRED, paste0(prefix,"PREDICTIONS.csv")), row.names=FALSE)
  write.csv(thr_df,  file.path(OUTDIR_THR, paste0(prefix,"THRESHOLD_GRID.csv")), row.names=FALSE)
  write.csv(opt_df,  file.path(OUTDIR_SUM, paste0(prefix,"OPTIMAL.csv")), row.names=FALSE)
  write.csv(yhat_df, file.path(OUTDIR_DIAG, paste0(prefix,"YHAT_STATS.csv")), row.names=FALSE)

  # Ozet
  mean_acc  <- mean(opt_df$test_Acc_05, na.rm=TRUE)
  mean_flip <- mean(opt_df$test_Acc_flip_05, na.rm=TRUE)
  fw <- sum(opt_df$test_flip_beats_naive, na.rm=TRUE)
  mc <- sum(opt_df$test_is_MC_05, na.rm=TRUE)
  cross_arch_rows[[length(cross_arch_rows)+1]] <- data.frame(
    arch=arch_name, n_config=nrow(opt_df), naive_acc=naive_acc,
    mean_acc=mean_acc, mean_acc_flip=mean_flip,
    flip_beats_naive_count=fw, mc_count=mc, stringsAsFactors=FALSE)

  cat(sprintf("\n[%s] OZET: Acc=%.3f flip=%.3f flip_wins=%d/%d MC=%d/%d\n",
              arch_name, mean_acc, mean_flip, fw, nrow(opt_df), mc, nrow(opt_df)))
}

# --- 10. Cross-architecture summary + KARAR ---
cross_df <- do.call(rbind, cross_arch_rows)
# BiLSTM referans ekle
cross_df <- rbind(cross_df, data.frame(
  arch="BiLSTM_v3b_ref", n_config=15, naive_acc=0.518,
  mean_acc=0.396, mean_acc_flip=0.604,
  flip_beats_naive_count=15, mc_count=0, stringsAsFactors=FALSE))
cross_df <- rbind(cross_df, data.frame(
  arch="BiLSTM_v3c_noCW_ref", n_config=15, naive_acc=0.518,
  mean_acc=0.436, mean_acc_flip=0.564,
  flip_beats_naive_count=15, mc_count=0, stringsAsFactors=FALSE))

write.csv(cross_df, file.path(OUTDIR_SUM, "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv"),
          row.names=FALSE)

cat("\n", strrep("=", 95), "\n", sep="")
cat("ADIM I.8 KARAR MATRISI — MIMARI ABLATION\n")
cat(strrep("=", 95), "\n", sep="")
cat("\nCROSS-ARCHITECTURE SUMMARY:\n")
print(cross_df)

new_archs <- c("SimpleRNN", "GRU", "Conv1D", "TCN", "Transformer")
total_new <- sum(cross_df$flip_beats_naive_count[cross_df$arch %in% new_archs])
total_cfg <- sum(cross_df$n_config[cross_df$arch %in% new_archs])
n_anti <- sum(cross_df$flip_beats_naive_count[cross_df$arch %in% new_archs] >= 12)

cat(sprintf("\n5 yeni mimari: flip_wins = %d / %d | anti-prediktif mimari sayisi: %d/5\n",
            total_new, total_cfg, n_anti))

if (n_anti >= 4) {
  cat("\n[A] MIMARI-BAGIMSIZ ANTI-PREDIKTIF:\n")
  cat("    4+ mimari anti-prediktif -> VERI OZELLIGI.\n")
  cat("    Yorum 3 COK GUCLENDI.\n")
} else if (n_anti <= 1) {
  cat("\n[B] BiLSTM-SPESIFIK:\n")
  cat("    Sadece 0-1 yeni mimari anti-prediktif -> BiLSTM artefakti.\n")
  cat("    Yorum 3 ZAYIFLADI.\n")
} else {
  cat("\n[C] HETEROJEN:\n")
  cat(sprintf("    %d/5 mimari anti-prediktif -- karisik sonuc.\n", n_anti))
}

# --- 11. McNEMAR TESTI (her mimari cifti) ---
cat("\n", strrep("=", 95), "\n", sep="")
cat("McNEMAR TESTLERI (thr=0.5, seed=23, lambda=0)\n")
cat(strrep("=", 95), "\n", sep="")
cat("(Iki siniflandirici arasinda anlamli fark var mi?)\n\n")

# Her mimari icin seed=23, lambda=0 tahminlerini topla
all_preds_file <- file.path(OUTDIR_SUM, "mcaware_multi_arch_ALL_PREDS_seed23.csv")
all_preds <- list()
for (an in names(ARCH_BUILDERS)) {
  fn <- file.path(OUTDIR_PRED, paste0("mcaware_multi_arch_", an, "_PREDICTIONS.csv"))
  if (file.exists(fn)) {
    d <- read.csv(fn)
    d23 <- d[d$seed == 23 & d$lambda == 0 & d$set == "test", ]
    if (nrow(d23) > 0) all_preds[[an]] <- d23
  }
}
# BiLSTM referans: v3b predictions
bilstm_fn <- file.path(OUTDIR_PRED, "mcaware_BiLSTM_v3b_window_PREDICTIONS.csv")
if (file.exists(bilstm_fn)) {
  bd <- read.csv(bilstm_fn)
  bd23 <- bd[bd$seed == 23 & bd$lambda == 0 & bd$set == "test", ]
  if (nrow(bd23) > 0) all_preds[["BiLSTM"]] <- bd23
}

mcnemar_rows <- list()
arch_names <- names(all_preds)
if (length(arch_names) >= 2) {
  for (i in 1:(length(arch_names)-1)) {
    for (j in (i+1):length(arch_names)) {
      a1 <- arch_names[i]; a2 <- arch_names[j]
      p1 <- as.integer(all_preds[[a1]]$yhat > 0.5)
      p2 <- as.integer(all_preds[[a2]]$yhat > 0.5)
      y  <- all_preds[[a1]]$y_true
      n_samp <- min(length(p1), length(p2), length(y))
      p1 <- p1[1:n_samp]; p2 <- p2[1:n_samp]; y <- y[1:n_samp]
      c1 <- (p1 == y); c2 <- (p2 == y) # dogru mu?
      # McNemar 2x2: c1_right&c2_wrong vs c1_wrong&c2_right
      b <- sum(c1 & !c2); cc <- sum(!c1 & c2)
      if ((b + cc) > 0) {
        # McNemar chi-sq (continuity corrected)
        chi2 <- (abs(b - cc) - 1)^2 / (b + cc)
        p_val <- 1 - pchisq(chi2, df = 1)
      } else { chi2 <- 0; p_val <- 1.0 }
      sig <- if (p_val < 0.05) "*SIG*" else "n.s."
      cat(sprintf("  %s vs %s: b=%d c=%d chi2=%.2f p=%.4f %s\n",
                  a1, a2, b, cc, chi2, p_val, sig))
      mcnemar_rows[[length(mcnemar_rows)+1]] <- data.frame(
        arch1=a1, arch2=a2, b_only_a1_correct=b, c_only_a2_correct=cc,
        chi2=chi2, p_value=p_val, significant=sig, stringsAsFactors=FALSE)
    }
  }
  mcnemar_df <- do.call(rbind, mcnemar_rows)
  write.csv(mcnemar_df, file.path(OUTDIR_DIAG, "mcaware_multi_arch_McNEMAR.csv"), row.names=FALSE)
  cat("\nMcNemar CSV kaydedildi.\n")
} else {
  cat("McNemar icin yeterli mimari yok, atlandi.\n")
}

 # ===========================================================================
# MC-AWARE PROTOTYPE — MULTI-ARCHITECTURE v4 (ADIM I.8: MIMARI ABLATION)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   BiLSTM'de 45/45 anti-prediktif gozlem THYAO-spesifik ve CW-bagimsiz.
#   Soru: Bu BILSTM'e mi ozgu yoksa VERI OZELLIGI mi?
#   Test: 5 mimari ayni veri/pencere/grid ile kosturulur:
#     SimpleRNN, GRU, Conv1D, TCN (dilated causal), Transformer (MHA)
#   Eger hepsi anti-prediktif → VERI ozelligi (Yorum 3 cok guclenir)
#   Eger sadece BiLSTM → mimari artefakt (Yorum 3 zayiflar)
#   + McNemar testi: mimari cifleri arasinda istatistiksel fark
#
# KARAR MATRISI:
#   [A] >=4/5 mimari anti-prediktif → VERI OZELLIGI
#   [B] <=2/5 mimari anti-prediktif → MIMARIYE BAGLI artefakt
#   [C] Karisik → Heterojen
#
# CIKTI: 5 mimari x 4 CSV = 20 CSV + CROSS_ARCH_SUMMARY + McNEMAR
# Calistirma: RStudio → Ctrl+Shift+S → ~90-120 dk → 22 CSV
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ---
WORKDIR <- here::here()
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse); library(TTR); library(zoo)
  library(keras3); library(tensorflow); library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — MULTI-ARCHITECTURE v4 (ADIM I.8)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Mimariler: SimpleRNN, GRU, Conv1D, TCN, Transformer\n")
cat("Referans: BiLSTM v3b (Acc=0.396, flip=0.604, 15/15)\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { warning("OUTDIR yok, WORKDIR kullaniliyor"); OUTDIR <- WORKDIR }

# --- 1. THYAO veri cekme (v3b/v3c ile AYNI) ---
cat("THYAO verisi cekiliyor...\n")
getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
thyao_xts <- THYAO.IS
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
stoch_vals     <- TTR::stoch(thyao_df[, c("High", "Low", "Close")])
thyao_df$SO_K  <- stoch_vals[, "fastK"]
thyao_df$SO_D  <- stoch_vals[, "fastD"]
adx_vals       <- TTR::ADX(thyao_df[, c("High", "Low", "Close")])
thyao_df$ADX   <- adx_vals[, "ADX"]

tryCatch({
  getSymbols("USDTRY=X", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  usdtry_df <- data.frame(Date=as.character(index(`USDTRY=X`)), USDTRY=as.numeric(Cl(`USDTRY=X`)))
}, error=function(e) { usdtry_df <<- data.frame(Date=character(0), USDTRY=numeric(0)) })
tryCatch({
  getSymbols("CL=F", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  oil_df <- data.frame(Date=as.character(index(`CL=F`)), Oil=as.numeric(Cl(`CL=F`)))
}, error=function(e) { oil_df <<- data.frame(Date=character(0), Oil=numeric(0)) })
tryCatch({
  getSymbols("INTDSRTRM193N", src="FRED", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  tcmb_df <- data.frame(Date=as.Date(index(INTDSRTRM193N)), TCMB_Rate=as.numeric(INTDSRTRM193N))
  tcmb_daily <- data.frame(Date=as.Date(thyao_df$Date)) %>%
    mutate(YearMonth=format(Date,"%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth=format(Date,"%Y-%m")), by="YearMonth") %>%
    select(Date=Date.x, TCMB_Rate)
}, error=function(e) { tcmb_daily <<- data.frame(Date=as.Date(thyao_df$Date), TCMB_Rate=NA_real_) })

thyao_final <- thyao_df %>%
  left_join(usdtry_df, by="Date") %>% left_join(oil_df, by="Date") %>%
  left_join(tcmb_daily %>% mutate(Date=as.character(Date)), by="Date")
thyao_final$USDTRY    <- zoo::na.locf(thyao_final$USDTRY, na.rm=FALSE)
thyao_final$Oil       <- zoo::na.locf(thyao_final$Oil, na.rm=FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm=FALSE)
thyao_final <- thyao_final[28:nrow(thyao_final), ] %>% drop_na()
cat(sprintf("Final THYAO: %d satir\n", nrow(thyao_final)))

# --- 2. Pencereleme (v3b ile AYNI - duzeltilmis) ---
IN_LEN <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec

# --- 3. Split ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr+1L):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
X_te <- X_arr[(i_va+1L):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+1L):n_total]
cat(sprintf("Split: Train=%d Val=%d Test=%d\n", length(y_tr), length(y_va), length(y_te)))

naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
cat(sprintf("NAIVE BASELINE: %.4f\n\n", naive_acc))

# --- 4. Normalize ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 5. Loss ---
make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) {
      bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    } else { bce }
  }
}

# --- 6. MODEL BUILDERS (BU SCRIPTIN KALBI — 5 MIMARI) ---

build_simple_rnn <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_simple_rnn(units = 64, activation = "tanh", return_sequences = FALSE) %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_gru <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_gru(units = 64, activation = "tanh", return_sequences = TRUE) %>%
    keras3::layer_gru(units = 32, activation = "tanh", return_sequences = FALSE) %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_conv1d <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_conv_1d(filters = 64, kernel_size = 1, activation = "relu",
                          padding = "same") %>%
    keras3::layer_conv_1d(filters = 32, kernel_size = 1, activation = "relu",
                          padding = "same") %>%
    keras3::layer_global_average_pooling_1d() %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_tcn <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  # TCN = dilated causal convolutions (IN_LEN=2 icin dilation=1 yeterli)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_conv_1d(filters = 64, kernel_size = 2, activation = "relu",
                          padding = "causal", dilation_rate = 1) %>%
    keras3::layer_conv_1d(filters = 32, kernel_size = 1, activation = "relu",
                          padding = "causal") %>%
    keras3::layer_global_average_pooling_1d() %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

build_transformer <- function(seed, lambda_mc) {
  keras3::set_random_seed(seed)
  # Functional API: Input -> MultiHeadAttention -> Dense
  inp <- keras3::layer_input(shape = c(IN_LEN, F_DIM))
  # Positional bilgi icin Dense projection
  x <- inp %>% keras3::layer_dense(units = 64, activation = "relu")
  # Self-attention
  attn_out <- keras3::layer_multi_head_attention(
    num_heads = 2, key_dim = 32)(x, x)
  x <- keras3::layer_add(list(x, attn_out))  # residual
  x <- keras3::layer_layer_normalization()(x)
  x <- keras3::layer_global_average_pooling_1d()(x)
  x <- keras3::layer_dropout(rate = 0.4)(x)
  out <- keras3::layer_dense(units = 1, activation = "sigmoid")(x)
  model <- keras3::keras_model(inputs = inp, outputs = out)
  model %>% keras3::compile(optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc), metrics = c("accuracy"))
  model
}

ARCH_BUILDERS <- list(
  SimpleRNN   = build_simple_rnn,
  GRU         = build_gru,
  Conv1D      = build_conv1d,
  TCN         = build_tcn,
  Transformer = build_transformer
)

# --- 7. Metrik ---
compute_metrics <- function(y_true, yhat, threshold) {
  pred <- as.integer(yhat > threshold)
  tp <- sum(pred==1 & y_true==1); tn <- sum(pred==0 & y_true==0)
  fp <- sum(pred==1 & y_true==0); fn <- sum(pred==0 & y_true==1)
  n <- length(y_true); acc <- (tp+tn)/n
  sens <- if ((tp+fn)>0) tp/(tp+fn) else NA_real_
  spec <- if ((tn+fp)>0) tn/(tn+fp) else NA_real_
  prec_ <- if ((tp+fp)>0) tp/(tp+fp) else NA_real_
  f1 <- if (!is.na(prec_)&&!is.na(sens)&&(prec_+sens)>0) 2*prec_*sens/(prec_+sens) else NA_real_
  bacc <- if (!is.na(sens)&&!is.na(spec)) (sens+spec)/2 else NA_real_
  is_mc <- isTRUE(spec==0)||isTRUE(sens==0)||is.na(spec)||is.na(sens)
  list(Acc=acc, Sens=sens, Spec=spec, Prec=prec_, F1=f1,
       BalAcc=bacc, is_MC=is_mc, Acc_flip=1-acc)
}

# --- 8. Train + predict ---
train_and_predict <- function(builder_fn, seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- builder_fn(seed, lambda_mc)
    # CW=balanced (v3b ile ayni)
    n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1); nt <- length(y_tr)
    w0 <- nt / (2 * n0); w1 <- nt / (2 * n1)
    cw <- list("0" = w0, "1" = w1)
    cb <- keras3::callback_early_stopping(monitor="val_accuracy",
                                           patience=5L, restore_best_weights=TRUE)
    model %>% keras3::fit(X_tr, y_tr, validation_data=list(X_va, y_va),
                          epochs=50L, batch_size=32L, verbose=0L,
                          callbacks=list(cb), class_weight=cw)
    yhat_val  <- as.numeric(predict(model, X_va, verbose=0L))
    yhat_test <- as.numeric(predict(model, X_te, verbose=0L))
    list(yhat_val=yhat_val, yhat_test=yhat_test, error=NA_character_)
  }, error=function(e) {
    list(yhat_val=rep(NA_real_, length(y_va)),
         yhat_test=rep(NA_real_, length(y_te)), error=conditionMessage(e))
  })
}

# --- 9. Grid ---
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cross_arch_rows <- list()

for (arch_name in names(ARCH_BUILDERS)) {
  builder_fn <- ARCH_BUILDERS[[arch_name]]
  cat(sprintf("\n%s\n", strrep("=", 95)))
  cat(sprintf("MIMARI: %s | %d lambda x %d seed = %d kosu\n",
              arch_name, length(LAMBDAS), length(SEEDS), length(LAMBDAS)*length(SEEDS)))
  cat(sprintf("%s\n", strrep("=", 95)))

  predictions_list <- list(); threshold_rows <- list()
  optimal_rows <- list(); yhat_stats_rows <- list()

  t0 <- Sys.time()
  for (lam in LAMBDAS) {
    for (sd_seed in SEEDS) {
      cat(sprintf("\n[%s] lambda=%.2f seed=%d ...\n", arch_name, lam, sd_seed))
      pred <- train_and_predict(builder_fn, sd_seed, lam)
      if (!is.na(pred$error)) { cat(" HATA:", pred$error, "\n"); next }

      yhat_stats_rows[[length(yhat_stats_rows)+1]] <- data.frame(
        arch=arch_name, lambda=lam, seed=sd_seed,
        test_min=min(pred$yhat_test), test_max=max(pred$yhat_test),
        test_mean=mean(pred$yhat_test), test_range=max(pred$yhat_test)-min(pred$yhat_test),
        stringsAsFactors=FALSE)

      for (i in seq_along(y_te)) {
        predictions_list[[length(predictions_list)+1]] <- data.frame(
          arch=arch_name, lambda=lam, seed=sd_seed, set="test",
          sample_id=i, yhat=pred$yhat_test[i], y_true=y_te[i], stringsAsFactors=FALSE)
      }
      for (thr in THRESHOLDS) {
        m_test <- compute_metrics(y_te, pred$yhat_test, thr)
        threshold_rows[[length(threshold_rows)+1]] <- data.frame(
          arch=arch_name, lambda=lam, seed=sd_seed, threshold=thr,
          Acc=m_test$Acc, Spec=m_test$Spec, Sens=m_test$Sens,
          BalAcc=m_test$BalAcc, Acc_flip=m_test$Acc_flip,
          is_MC=m_test$is_MC, stringsAsFactors=FALSE)
      }

      val_bacc <- sapply(THRESHOLDS, function(thr) {
        m <- compute_metrics(y_va, pred$yhat_val, thr)
        if (is.na(m$BalAcc)) -Inf else m$BalAcc })
      best_thr <- THRESHOLDS[which.max(val_bacc)]
      m05 <- compute_metrics(y_te, pred$yhat_test, 0.5)

      optimal_rows[[length(optimal_rows)+1]] <- data.frame(
        arch=arch_name, lambda=lam, seed=sd_seed, best_thr=best_thr,
        test_Acc_05=m05$Acc, test_Spec_05=m05$Spec, test_Sens_05=m05$Sens,
        test_Acc_flip_05=m05$Acc_flip,
        test_flip_beats_naive=m05$Acc_flip > naive_acc,
        test_is_MC_05=m05$is_MC, stringsAsFactors=FALSE)

      cat(sprintf("  yhat: min=%.3f max=%.3f | Acc=%.3f flip=%.3f MC=%s\n",
                  min(pred$yhat_test), max(pred$yhat_test),
                  m05$Acc, m05$Acc_flip, if(m05$is_MC) "YES" else "no"))
    }
  }
  t1 <- Sys.time()
  cat(sprintf("\n[%s] Sure: %.1f dk\n", arch_name, as.numeric(difftime(t1,t0,units="mins"))))

  # CSV kaydet
  pred_df <- do.call(rbind, predictions_list)
  thr_df  <- do.call(rbind, threshold_rows)
  opt_df  <- do.call(rbind, optimal_rows)
  yhat_df <- do.call(rbind, yhat_stats_rows)

  prefix <- paste0("mcaware_multi_arch_", arch_name, "_")
  write.csv(pred_df, file.path(OUTDIR_PRED, paste0(prefix,"PREDICTIONS.csv")), row.names=FALSE)
  write.csv(thr_df,  file.path(OUTDIR_THR, paste0(prefix,"THRESHOLD_GRID.csv")), row.names=FALSE)
  write.csv(opt_df,  file.path(OUTDIR_SUM, paste0(prefix,"OPTIMAL.csv")), row.names=FALSE)
  write.csv(yhat_df, file.path(OUTDIR_DIAG, paste0(prefix,"YHAT_STATS.csv")), row.names=FALSE)

  # Ozet
  mean_acc  <- mean(opt_df$test_Acc_05, na.rm=TRUE)
  mean_flip <- mean(opt_df$test_Acc_flip_05, na.rm=TRUE)
  fw <- sum(opt_df$test_flip_beats_naive, na.rm=TRUE)
  mc <- sum(opt_df$test_is_MC_05, na.rm=TRUE)
  cross_arch_rows[[length(cross_arch_rows)+1]] <- data.frame(
    arch=arch_name, n_config=nrow(opt_df), naive_acc=naive_acc,
    mean_acc=mean_acc, mean_acc_flip=mean_flip,
    flip_beats_naive_count=fw, mc_count=mc, stringsAsFactors=FALSE)

  cat(sprintf("\n[%s] OZET: Acc=%.3f flip=%.3f flip_wins=%d/%d MC=%d/%d\n",
              arch_name, mean_acc, mean_flip, fw, nrow(opt_df), mc, nrow(opt_df)))
}

# --- 10. Cross-architecture summary + KARAR ---
cross_df <- do.call(rbind, cross_arch_rows)
# BiLSTM referans ekle
cross_df <- rbind(cross_df, data.frame(
  arch="BiLSTM_v3b_ref", n_config=15, naive_acc=0.518,
  mean_acc=0.396, mean_acc_flip=0.604,
  flip_beats_naive_count=15, mc_count=0, stringsAsFactors=FALSE))
cross_df <- rbind(cross_df, data.frame(
  arch="BiLSTM_v3c_noCW_ref", n_config=15, naive_acc=0.518,
  mean_acc=0.436, mean_acc_flip=0.564,
  flip_beats_naive_count=15, mc_count=0, stringsAsFactors=FALSE))

write.csv(cross_df, file.path(OUTDIR_SUM, "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv"),
          row.names=FALSE)

cat("\n", strrep("=", 95), "\n", sep="")
cat("ADIM I.8 KARAR MATRISI — MIMARI ABLATION\n")
cat(strrep("=", 95), "\n", sep="")
cat("\nCROSS-ARCHITECTURE SUMMARY:\n")
print(cross_df)

new_archs <- c("SimpleRNN", "GRU", "Conv1D", "TCN", "Transformer")
total_new <- sum(cross_df$flip_beats_naive_count[cross_df$arch %in% new_archs])
total_cfg <- sum(cross_df$n_config[cross_df$arch %in% new_archs])
n_anti <- sum(cross_df$flip_beats_naive_count[cross_df$arch %in% new_archs] >= 12)

cat(sprintf("\n5 yeni mimari: flip_wins = %d / %d | anti-prediktif mimari sayisi: %d/5\n",
            total_new, total_cfg, n_anti))

if (n_anti >= 4) {
  cat("\n[A] MIMARI-BAGIMSIZ ANTI-PREDIKTIF:\n")
  cat("    4+ mimari anti-prediktif -> VERI OZELLIGI.\n")
  cat("    Yorum 3 COK GUCLENDI.\n")
} else if (n_anti <= 1) {
  cat("\n[B] BiLSTM-SPESIFIK:\n")
  cat("    Sadece 0-1 yeni mimari anti-prediktif -> BiLSTM artefakti.\n")
  cat("    Yorum 3 ZAYIFLADI.\n")
} else {
  cat("\n[C] HETEROJEN:\n")
  cat(sprintf("    %d/5 mimari anti-prediktif -- karisik sonuc.\n", n_anti))
}

# --- 11. McNEMAR TESTI (her mimari cifti) ---
cat("\n", strrep("=", 95), "\n", sep="")
cat("McNEMAR TESTLERI (thr=0.5, seed=23, lambda=0)\n")
cat(strrep("=", 95), "\n", sep="")
cat("(Iki siniflandirici arasinda anlamli fark var mi?)\n\n")

# Her mimari icin seed=23, lambda=0 tahminlerini topla
all_preds_file <- file.path(OUTDIR_SUM, "mcaware_multi_arch_ALL_PREDS_seed23.csv")
all_preds <- list()
for (an in names(ARCH_BUILDERS)) {
  fn <- file.path(OUTDIR_PRED, paste0("mcaware_multi_arch_", an, "_PREDICTIONS.csv"))
  if (file.exists(fn)) {
    d <- read.csv(fn)
    d23 <- d[d$seed == 23 & d$lambda == 0 & d$set == "test", ]
    if (nrow(d23) > 0) all_preds[[an]] <- d23
  }
}
# BiLSTM referans: v3b predictions
bilstm_fn <- file.path(OUTDIR_PRED, "mcaware_BiLSTM_v3b_window_PREDICTIONS.csv")
if (file.exists(bilstm_fn)) {
  bd <- read.csv(bilstm_fn)
  bd23 <- bd[bd$seed == 23 & bd$lambda == 0 & bd$set == "test", ]
  if (nrow(bd23) > 0) all_preds[["BiLSTM"]] <- bd23
}

mcnemar_rows <- list()
arch_names <- names(all_preds)
if (length(arch_names) >= 2) {
  for (i in 1:(length(arch_names)-1)) {
    for (j in (i+1):length(arch_names)) {
      a1 <- arch_names[i]; a2 <- arch_names[j]
      p1 <- as.integer(all_preds[[a1]]$yhat > 0.5)
      p2 <- as.integer(all_preds[[a2]]$yhat > 0.5)
      y  <- all_preds[[a1]]$y_true
      n_samp <- min(length(p1), length(p2), length(y))
      p1 <- p1[1:n_samp]; p2 <- p2[1:n_samp]; y <- y[1:n_samp]
      c1 <- (p1 == y); c2 <- (p2 == y) # dogru mu?
      # McNemar 2x2: c1_right&c2_wrong vs c1_wrong&c2_right
      b <- sum(c1 & !c2); cc <- sum(!c1 & c2)
      if ((b + cc) > 0) {
        # McNemar chi-sq (continuity corrected)
        chi2 <- (abs(b - cc) - 1)^2 / (b + cc)
        p_val <- 1 - pchisq(chi2, df = 1)
      } else { chi2 <- 0; p_val <- 1.0 }
      sig <- if (p_val < 0.05) "*SIG*" else "n.s."
      cat(sprintf("  %s vs %s: b=%d c=%d chi2=%.2f p=%.4f %s\n",
                  a1, a2, b, cc, chi2, p_val, sig))
      mcnemar_rows[[length(mcnemar_rows)+1]] <- data.frame(
        arch1=a1, arch2=a2, b_only_a1_correct=b, c_only_a2_correct=cc,
        chi2=chi2, p_value=p_val, significant=sig, stringsAsFactors=FALSE)
    }
  }
  mcnemar_df <- do.call(rbind, mcnemar_rows)
  write.csv(mcnemar_df, file.path(OUTDIR_DIAG, "mcaware_multi_arch_McNEMAR.csv"), row.names=FALSE)
  cat("\nMcNemar CSV kaydedildi.\n")
} else {
  cat("McNemar icin yeterli mimari yok, atlandi.\n")
}

cat(sprintf("\nTum CSV'ler kaydedildi: %s\n", OUTDIR))
cat("\nADIM I.8 TAMAMLANDI — sonuclari PROJE_DURUMU.txt Bolum 10.29 olarak isle.\n")
.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' )
cat("\nADIM I.8 TAMAMLANDI — sonuclari PROJE_DURUMU.txt Bolum 10.29 olarak isle.\n")

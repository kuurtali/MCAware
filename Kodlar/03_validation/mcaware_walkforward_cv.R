# ===========================================================================
# MC-AWARE — WALK-FORWARD CV (ADIM I.9: TEK SPLIT RISKI TESTI)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   R1 riski: Tüm deneyler AYNI train/test split'i kullanıyor.
#   Test döneminde rejim değişimi varsa TÜM modeller aynı şekilde
#   başarısız olur. Walk-forward CV ile bunu kontrol ediyoruz.
#
#   YÖNTEM: Expanding window walk-forward:
#     Fold 1: Train=[1:500],  Test=[501:600]
#     Fold 2: Train=[1:600],  Test=[601:700]
#     ...
#     Her fold'da BiLSTM (CW=balanced, lambda=0, seed=42) eğitilir.
#     Her fold'un anti-prediktif mi değil mi olduğu raporlanır.
#
#   KARAR: Eğer çoğu fold anti-prediktif → TEK SPLIT artefaktı değil.
#          Eğer sadece son fold anti-prediktif → rejim değişimi etkisi.
#
# CIKTI: mcaware_walkforward_RESULTS.csv
# Süre: ~30-45 dk (fold sayısına bağlı)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


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
cat("MC-AWARE — WALK-FORWARD CV (ADIM I.9)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

# --- Bidirectional API ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- THYAO veri (v3b ile ayni) ---
cat("THYAO verisi cekiliyor...\n")
getSymbols("THYAO.IS", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
thyao_xts <- THYAO.IS
thyao_df <- data.frame(
  Date=as.character(index(thyao_xts)),
  Open=as.numeric(Op(thyao_xts)), High=as.numeric(Hi(thyao_xts)),
  Low=as.numeric(Lo(thyao_xts)), Close=as.numeric(Cl(thyao_xts)),
  Volume=as.numeric(Vo(thyao_xts)))
thyao_df <- thyao_df[thyao_df$Volume > 0, ]
thyao_df <- thyao_df[complete.cases(thyao_df[, c("Open","High","Low","Close")]), ]

thyao_df$RSI <- TTR::RSI(thyao_df$Close, n=14)
macd_vals <- TTR::MACD(thyao_df$Close)
thyao_df$MACD <- macd_vals[,"macd"]
thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n=12)
thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n=26)
stoch_vals <- TTR::stoch(thyao_df[, c("High","Low","Close")])
thyao_df$SO_K <- stoch_vals[,"fastK"]; thyao_df$SO_D <- stoch_vals[,"fastD"]
adx_vals <- TTR::ADX(thyao_df[, c("High","Low","Close")])
thyao_df$ADX <- adx_vals[,"ADX"]

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
thyao_final$USDTRY <- zoo::na.locf(thyao_final$USDTRY, na.rm=FALSE)
thyao_final$Oil <- zoo::na.locf(thyao_final$Oil, na.rm=FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm=FALSE)
thyao_final <- thyao_final[28:nrow(thyao_final), ] %>% drop_na()

# --- Pencereleme ---
IN_LEN <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop=FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
n_total <- length(y_arr)
cat(sprintf("Toplam pencere: %d\n", n_total))

# --- Walk-forward parametreleri ---
MIN_TRAIN <- 500L   # minimum egitim seti
TEST_SIZE <- 200L   # her fold'un test seti
STEP_SIZE <- 200L   # fold'lar arasi kayma
SEED <- 42L; LAMBDA <- 0.0

folds <- list()
start_test <- MIN_TRAIN + 1L
while (start_test + TEST_SIZE - 1 <= n_total) {
  end_test <- start_test + TEST_SIZE - 1L
  folds[[length(folds) + 1]] <- list(
    train_idx = 1:(start_test - 1),
    test_idx  = start_test:end_test
  )
  start_test <- start_test + STEP_SIZE
}
cat(sprintf("Walk-forward: %d fold (min_train=%d, test=%d, step=%d)\n\n",
            length(folds), MIN_TRAIN, TEST_SIZE, STEP_SIZE))

# --- Loss + model ---
make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) { bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    } else { bce }
  }
}

# --- Fold loop ---
fold_results <- list()
t0_all <- Sys.time()

for (fi in seq_along(folds)) {
  fold <- folds[[fi]]
  cat(sprintf("=== FOLD %d/%d: Train=[1:%d] Test=[%d:%d] ===\n",
              fi, length(folds), max(fold$train_idx),
              min(fold$test_idx), max(fold$test_idx)))

  X_tr_f <- X_arr[fold$train_idx,,, drop=FALSE]
  y_tr_f <- y_arr[fold$train_idx]
  X_te_f <- X_arr[fold$test_idx,,, drop=FALSE]
  y_te_f <- y_arr[fold$test_idx]

  # Normalize (train stats)
  mu_f <- apply(X_tr_f, c(2,3), mean)
  sd_f <- apply(X_tr_f, c(2,3), stats::sd) + 1e-8
  norm_f <- function(A) sweep(sweep(A, c(2,3), mu_f, "-"), c(2,3), sd_f, "/")
  X_tr_n <- norm_f(X_tr_f); X_te_n <- norm_f(X_te_f)

  # CW balanced
  n0 <- sum(y_tr_f==0); n1 <- sum(y_tr_f==1); nt <- length(y_tr_f)
  w0 <- nt/(2*n0); w1 <- nt/(2*n1)
  cw <- list("0"=w0, "1"=w1)
  naive_f <- mean(y_te_f == as.integer(mean(y_tr_f) > 0.5))

  keras3::clear_session()
  tryCatch({
    keras3::set_random_seed(SEED)
    inner <- keras3::layer_lstm(units=64, activation="tanh", return_sequences=FALSE)
    model <- keras3::keras_model_sequential(input_shape=c(IN_LEN, F_DIM))
    model <- bidir_fn(model, inner, merge_mode="concat")
    model <- model %>%
      keras3::layer_dropout(rate=0.4) %>%
      keras3::layer_dense(units=1, activation="sigmoid")
    model %>% keras3::compile(optimizer=keras3::optimizer_adam(),
                              loss=make_mc_loss(LAMBDA), metrics=c("accuracy"))

    # Val = last 15% of train
    n_tr <- length(y_tr_f)
    i_va_start <- floor(n_tr * 0.85) + 1
    X_va_f <- X_tr_n[i_va_start:n_tr,,, drop=FALSE]
    y_va_f <- y_tr_f[i_va_start:n_tr]
    X_tr_real <- X_tr_n[1:(i_va_start-1),,, drop=FALSE]
    y_tr_real <- y_tr_f[1:(i_va_start-1)]

    cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L,
                                           restore_best_weights=TRUE)
    model %>% keras3::fit(X_tr_real, y_tr_real, validation_data=list(X_va_f, y_va_f),
                          epochs=50L, batch_size=32L, verbose=0L,
                          callbacks=list(cb), class_weight=cw)

    yhat <- as.numeric(predict(model, X_te_n, verbose=0L))
    pred <- as.integer(yhat > 0.5)
    acc <- mean(pred == y_te_f)
    acc_flip <- 1 - acc
    tp <- sum(pred==1 & y_te_f==1); tn <- sum(pred==0 & y_te_f==0)
    spec <- if (sum(y_te_f==0)>0) tn/sum(y_te_f==0) else NA
    sens <- if (sum(y_te_f==1)>0) tp/sum(y_te_f==1) else NA
    is_mc <- isTRUE(spec==0)||isTRUE(sens==0)||is.na(spec)||is.na(sens)
    flip_beats <- acc_flip > naive_f

    cat(sprintf("  Acc=%.3f flip=%.3f naive=%.3f flip_beats=%s MC=%s yhat=[%.3f,%.3f]\n",
                acc, acc_flip, naive_f, flip_beats, is_mc,
                min(yhat), max(yhat)))

    fold_results[[fi]] <- data.frame(
      fold=fi, train_end=max(fold$train_idx), test_start=min(fold$test_idx),
      test_end=max(fold$test_idx), n_train=length(y_tr_f), n_test=length(y_te_f),
      up_pct_train=mean(y_tr_f), up_pct_test=mean(y_te_f),
      naive_acc=naive_f, acc=acc, acc_flip=acc_flip,
      flip_beats_naive=flip_beats, is_MC=is_mc,
      yhat_min=min(yhat), yhat_max=max(yhat), yhat_range=max(yhat)-min(yhat),
      sens=sens, spec=spec, error=NA_character_, stringsAsFactors=FALSE)
  }, error=function(e) {
    cat("  HATA:", conditionMessage(e), "\n")
    fold_results[[fi]] <<- data.frame(
      fold=fi, train_end=max(fold$train_idx), test_start=min(fold$test_idx),
      test_end=max(fold$test_idx), n_train=length(y_tr_f), n_test=length(y_te_f),
      up_pct_train=mean(y_tr_f), up_pct_test=mean(y_te_f),
      naive_acc=naive_f, acc=NA, acc_flip=NA, flip_beats_naive=NA, is_MC=NA,
      yhat_min=NA, yhat_max=NA, yhat_range=NA, sens=NA, spec=NA,
      error=conditionMessage(e), stringsAsFactors=FALSE)
  })
}

t1_all <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dk\n", as.numeric(difftime(t1_all, t0_all, units="mins"))))

# --- Sonuç ---
results_df <- do.call(rbind, fold_results)
write.csv(results_df, file.path(OUTDIR_SUM, "mcaware_walkforward_RESULTS.csv"), row.names=FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.9 WALK-FORWARD CV SONUCLARI\n")
cat(strrep("=", 80), "\n", sep="")
print(results_df[, c("fold","n_train","n_test","naive_acc","acc","acc_flip",
                       "flip_beats_naive","is_MC")])

n_folds <- nrow(results_df)
n_flip <- sum(results_df$flip_beats_naive, na.rm=TRUE)
n_mc <- sum(results_df$is_MC, na.rm=TRUE)

cat(sprintf("\n%d/%d fold anti-prediktif, %d/%d MC\n", n_flip, n_folds, n_mc, n_folds))

if (n_flip >= ceiling(n_folds * 0.75)) {
  cat("\n[A] WALK-FORWARD DA ANTI-PREDIKTIF:\n")
  cat("    Tek split artefakti DEGIL. Farkli donemler ayni davranisi gosteriyor.\n")
  cat("    R1 riski KAPANDI.\n")
} else if (n_flip <= floor(n_folds * 0.25)) {
  cat("\n[B] SADECE SON DONEMDE ANTI-PREDIKTIF:\n")
  cat("    Tek split artefakti OLABILIR. Rejim degisimi etkisi muhtemel.\n")
  cat("    R1 riski ACIK.\n")
} else {
  cat("\n[C] KARISIK:\n")
  cat(sprintf("    %d/%d fold anti-prediktif. Donem-bagimli etki var.\n", n_flip, n_folds))
}

 # ===========================================================================
# MC-AWARE — WALK-FORWARD CV (ADIM I.9: TEK SPLIT RISKI TESTI)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   R1 riski: Tüm deneyler AYNI train/test split'i kullanıyor.
#   Test döneminde rejim değişimi varsa TÜM modeller aynı şekilde
#   başarısız olur. Walk-forward CV ile bunu kontrol ediyoruz.
#
#   YÖNTEM: Expanding window walk-forward:
#     Fold 1: Train=[1:500],  Test=[501:600]
#     Fold 2: Train=[1:600],  Test=[601:700]
#     ...
#     Her fold'da BiLSTM (CW=balanced, lambda=0, seed=42) eğitilir.
#     Her fold'un anti-prediktif mi değil mi olduğu raporlanır.
#
#   KARAR: Eğer çoğu fold anti-prediktif → TEK SPLIT artefaktı değil.
#          Eğer sadece son fold anti-prediktif → rejim değişimi etkisi.
#
# CIKTI: mcaware_walkforward_RESULTS.csv
# Süre: ~30-45 dk (fold sayısına bağlı)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


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
cat("MC-AWARE — WALK-FORWARD CV (ADIM I.9)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

# --- Bidirectional API ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- THYAO veri (v3b ile ayni) ---
cat("THYAO verisi cekiliyor...\n")
getSymbols("THYAO.IS", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
thyao_xts <- THYAO.IS
thyao_df <- data.frame(
  Date=as.character(index(thyao_xts)),
  Open=as.numeric(Op(thyao_xts)), High=as.numeric(Hi(thyao_xts)),
  Low=as.numeric(Lo(thyao_xts)), Close=as.numeric(Cl(thyao_xts)),
  Volume=as.numeric(Vo(thyao_xts)))
thyao_df <- thyao_df[thyao_df$Volume > 0, ]
thyao_df <- thyao_df[complete.cases(thyao_df[, c("Open","High","Low","Close")]), ]

thyao_df$RSI <- TTR::RSI(thyao_df$Close, n=14)
macd_vals <- TTR::MACD(thyao_df$Close)
thyao_df$MACD <- macd_vals[,"macd"]
thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n=12)
thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n=26)
stoch_vals <- TTR::stoch(thyao_df[, c("High","Low","Close")])
thyao_df$SO_K <- stoch_vals[,"fastK"]; thyao_df$SO_D <- stoch_vals[,"fastD"]
adx_vals <- TTR::ADX(thyao_df[, c("High","Low","Close")])
thyao_df$ADX <- adx_vals[,"ADX"]

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
thyao_final$USDTRY <- zoo::na.locf(thyao_final$USDTRY, na.rm=FALSE)
thyao_final$Oil <- zoo::na.locf(thyao_final$Oil, na.rm=FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm=FALSE)
thyao_final <- thyao_final[28:nrow(thyao_final), ] %>% drop_na()

# --- Pencereleme ---
IN_LEN <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop=FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
n_total <- length(y_arr)
cat(sprintf("Toplam pencere: %d\n", n_total))

# --- Walk-forward parametreleri ---
MIN_TRAIN <- 500L   # minimum egitim seti
TEST_SIZE <- 200L   # her fold'un test seti
STEP_SIZE <- 200L   # fold'lar arasi kayma
SEED <- 42L; LAMBDA <- 0.0

folds <- list()
start_test <- MIN_TRAIN + 1L
while (start_test + TEST_SIZE - 1 <= n_total) {
  end_test <- start_test + TEST_SIZE - 1L
  folds[[length(folds) + 1]] <- list(
    train_idx = 1:(start_test - 1),
    test_idx  = start_test:end_test
  )
  start_test <- start_test + STEP_SIZE
}
cat(sprintf("Walk-forward: %d fold (min_train=%d, test=%d, step=%d)\n\n",
            length(folds), MIN_TRAIN, TEST_SIZE, STEP_SIZE))

# --- Loss + model ---
make_mc_loss <- function(lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    bce <- -(y_true * keras3::op_log(yp) + (one - y_true) * keras3::op_log(one - yp))
    if (lambda_mc > 0) { bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    } else { bce }
  }
}

# --- Fold loop ---
fold_results <- list()
t0_all <- Sys.time()

for (fi in seq_along(folds)) {
  fold <- folds[[fi]]
  cat(sprintf("=== FOLD %d/%d: Train=[1:%d] Test=[%d:%d] ===\n",
              fi, length(folds), max(fold$train_idx),
              min(fold$test_idx), max(fold$test_idx)))

  X_tr_f <- X_arr[fold$train_idx,,, drop=FALSE]
  y_tr_f <- y_arr[fold$train_idx]
  X_te_f <- X_arr[fold$test_idx,,, drop=FALSE]
  y_te_f <- y_arr[fold$test_idx]

  # Normalize (train stats)
  mu_f <- apply(X_tr_f, c(2,3), mean)
  sd_f <- apply(X_tr_f, c(2,3), stats::sd) + 1e-8
  norm_f <- function(A) sweep(sweep(A, c(2,3), mu_f, "-"), c(2,3), sd_f, "/")
  X_tr_n <- norm_f(X_tr_f); X_te_n <- norm_f(X_te_f)

  # CW balanced
  n0 <- sum(y_tr_f==0); n1 <- sum(y_tr_f==1); nt <- length(y_tr_f)
  w0 <- nt/(2*n0); w1 <- nt/(2*n1)
  cw <- list("0"=w0, "1"=w1)
  naive_f <- mean(y_te_f == as.integer(mean(y_tr_f) > 0.5))

  keras3::clear_session()
  tryCatch({
    keras3::set_random_seed(SEED)
    inner <- keras3::layer_lstm(units=64, activation="tanh", return_sequences=FALSE)
    model <- keras3::keras_model_sequential(input_shape=c(IN_LEN, F_DIM))
    model <- bidir_fn(model, inner, merge_mode="concat")
    model <- model %>%
      keras3::layer_dropout(rate=0.4) %>%
      keras3::layer_dense(units=1, activation="sigmoid")
    model %>% keras3::compile(optimizer=keras3::optimizer_adam(),
                              loss=make_mc_loss(LAMBDA), metrics=c("accuracy"))

    # Val = last 15% of train
    n_tr <- length(y_tr_f)
    i_va_start <- floor(n_tr * 0.85) + 1
    X_va_f <- X_tr_n[i_va_start:n_tr,,, drop=FALSE]
    y_va_f <- y_tr_f[i_va_start:n_tr]
    X_tr_real <- X_tr_n[1:(i_va_start-1),,, drop=FALSE]
    y_tr_real <- y_tr_f[1:(i_va_start-1)]

    cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L,
                                           restore_best_weights=TRUE)
    model %>% keras3::fit(X_tr_real, y_tr_real, validation_data=list(X_va_f, y_va_f),
                          epochs=50L, batch_size=32L, verbose=0L,
                          callbacks=list(cb), class_weight=cw)

    yhat <- as.numeric(predict(model, X_te_n, verbose=0L))
    pred <- as.integer(yhat > 0.5)
    acc <- mean(pred == y_te_f)
    acc_flip <- 1 - acc
    tp <- sum(pred==1 & y_te_f==1); tn <- sum(pred==0 & y_te_f==0)
    spec <- if (sum(y_te_f==0)>0) tn/sum(y_te_f==0) else NA
    sens <- if (sum(y_te_f==1)>0) tp/sum(y_te_f==1) else NA
    is_mc <- isTRUE(spec==0)||isTRUE(sens==0)||is.na(spec)||is.na(sens)
    flip_beats <- acc_flip > naive_f

    cat(sprintf("  Acc=%.3f flip=%.3f naive=%.3f flip_beats=%s MC=%s yhat=[%.3f,%.3f]\n",
                acc, acc_flip, naive_f, flip_beats, is_mc,
                min(yhat), max(yhat)))

    fold_results[[fi]] <- data.frame(
      fold=fi, train_end=max(fold$train_idx), test_start=min(fold$test_idx),
      test_end=max(fold$test_idx), n_train=length(y_tr_f), n_test=length(y_te_f),
      up_pct_train=mean(y_tr_f), up_pct_test=mean(y_te_f),
      naive_acc=naive_f, acc=acc, acc_flip=acc_flip,
      flip_beats_naive=flip_beats, is_MC=is_mc,
      yhat_min=min(yhat), yhat_max=max(yhat), yhat_range=max(yhat)-min(yhat),
      sens=sens, spec=spec, error=NA_character_, stringsAsFactors=FALSE)
  }, error=function(e) {
    cat("  HATA:", conditionMessage(e), "\n")
    fold_results[[fi]] <<- data.frame(
      fold=fi, train_end=max(fold$train_idx), test_start=min(fold$test_idx),
      test_end=max(fold$test_idx), n_train=length(y_tr_f), n_test=length(y_te_f),
      up_pct_train=mean(y_tr_f), up_pct_test=mean(y_te_f),
      naive_acc=naive_f, acc=NA, acc_flip=NA, flip_beats_naive=NA, is_MC=NA,
      yhat_min=NA, yhat_max=NA, yhat_range=NA, sens=NA, spec=NA,
      error=conditionMessage(e), stringsAsFactors=FALSE)
  })
}

t1_all <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dk\n", as.numeric(difftime(t1_all, t0_all, units="mins"))))

# --- Sonuç ---
results_df <- do.call(rbind, fold_results)
write.csv(results_df, file.path(OUTDIR_SUM, "mcaware_walkforward_RESULTS.csv"), row.names=FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.9 WALK-FORWARD CV SONUCLARI\n")
cat(strrep("=", 80), "\n", sep="")
print(results_df[, c("fold","n_train","n_test","naive_acc","acc","acc_flip",
                       "flip_beats_naive","is_MC")])

n_folds <- nrow(results_df)
n_flip <- sum(results_df$flip_beats_naive, na.rm=TRUE)
n_mc <- sum(results_df$is_MC, na.rm=TRUE)

cat(sprintf("\n%d/%d fold anti-prediktif, %d/%d MC\n", n_flip, n_folds, n_mc, n_folds))

if (n_flip >= ceiling(n_folds * 0.75)) {
  cat("\n[A] WALK-FORWARD DA ANTI-PREDIKTIF:\n")
  cat("    Tek split artefakti DEGIL. Farkli donemler ayni davranisi gosteriyor.\n")
  cat("    R1 riski KAPANDI.\n")
} else if (n_flip <= floor(n_folds * 0.25)) {
  cat("\n[B] SADECE SON DONEMDE ANTI-PREDIKTIF:\n")
  cat("    Tek split artefakti OLABILIR. Rejim degisimi etkisi muhtemel.\n")
  cat("    R1 riski ACIK.\n")
} else {
  cat("\n[C] KARISIK:\n")
  cat(sprintf("    %d/%d fold anti-prediktif. Donem-bagimli etki var.\n", n_flip, n_folds))
}

cat(sprintf("\nCSV kaydedildi: %s\n", file.path(OUTDIR_SUM, "mcaware_walkforward_RESULTS.csv")))
cat("\nADIM I.9 TAMAMLANDI.\n")
.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' ))
cat("\nADIM I.9 TAMAMLANDI.\n")

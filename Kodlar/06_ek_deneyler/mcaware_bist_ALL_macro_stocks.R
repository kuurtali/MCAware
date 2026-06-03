# ===========================================================================
# MC-AWARE — BIST GENISLETILMIS HISSE HAVUZU (TAM KAPSAMLI FINAL TEST)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# ---------------------------------------------------------------------------
# AMACI:
#   11 hisselik geniş havuzda, GARAN v3b prototipinin "Birebir Aynısı" olan
#   en kapsamlı testi koşmak. Lambda varyasyonları (0, 0.05, 0.10) ve 
#   Threshold taramaları (0.30 - 0.70) dahil edilmiştir.
#
# CIKTI: 5 Farklı Global CSV Çıktısı
# ===========================================================================

if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)

WORKDIR <- here::here()
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
cat("MC-AWARE — BIST GENISLETILMIS HISSE HAVUZU (TAM KAPSAMLI)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- Ortak fonksiyonlar ---
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
  f1   <- if (!is.na(prec_) && !is.na(sens) && (prec_ + sens) > 0) 2 * prec_ * sens / (prec_ + sens) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) || is.na(spec) || is.na(sens)
  acc_flip <- 1 - acc
  list(Acc = acc, Sens = sens, Spec = spec, Prec = prec_,
       F1 = f1, BalAcc = bacc, is_MC = is_mc, Acc_flip = acc_flip,
       n_pred_Up = sum(pred), n_pred_Down = n - sum(pred))
}

build_bilstm <- function(seed, lambda_mc, IN_LEN, F_DIM) {
  keras3::set_random_seed(seed)
  inner_lstm <- keras3::layer_lstm(units = 64, activation = "tanh", return_sequences = FALSE)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
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

# --- Global lists for 5 CSVs ---
global_predictions <- list()
global_threshold_rows <- list()
global_optimal_rows <- list()
global_yhat_stats <- list()

# Grid parametreleri
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

# --- Ana fonksiyon: Tek hisse test ---
test_stock <- function(ticker, from="2018-01-01", to="2026-03-31") {
  cat(sprintf("\n%s\n", strrep("=", 80)))
  cat(sprintf("HISSE: %s\n", ticker))
  cat(sprintf("%s\n", strrep("=", 80)))

  xts_data <- tryCatch({
    getSymbols(ticker, from=from, to=to, auto.assign=TRUE, warnings=FALSE)
    get(gsub("[=]", "", ticker))
  }, error=function(e) {
    cat("HATA: Veri cekilemedi:", conditionMessage(e), "\n")
    return(NULL)
  })
  if (is.null(xts_data)) return(NULL)

  df <- data.frame(
    Date=as.character(index(xts_data)),
    Open=as.numeric(Op(xts_data)), High=as.numeric(Hi(xts_data)),
    Low=as.numeric(Lo(xts_data)), Close=as.numeric(Cl(xts_data)),
    Volume=as.numeric(Vo(xts_data)))
  df <- df[df$Volume > 0 & complete.cases(df[,c("Open","High","Low","Close")]), ]

  if (nrow(df) < 200) {
    cat(sprintf("YETERSIZ VERI: %d satir\n", nrow(df)))
    return(NULL)
  }

  df$RSI <- TTR::RSI(df$Close, n=14)
  macd_v <- TTR::MACD(df$Close); df$MACD <- macd_v[,"macd"]
  df$EMA12 <- TTR::EMA(df$Close, n=12); df$EMA26 <- TTR::EMA(df$Close, n=26)
  stoch_v <- TTR::stoch(df[,c("High","Low","Close")])
  df$SO_K <- stoch_v[,"fastK"]; df$SO_D <- stoch_v[,"fastD"]
  adx_v <- TTR::ADX(df[,c("High","Low","Close")]); df$ADX <- adx_v[,"ADX"]
  
  cat("Dis degiskenler cekiliyor (USDTRY, Oil, TCMB)...\n")
  tryCatch({
    getSymbols("USDTRY=X", from = "2018-01-01", to = "2026-03-31", auto.assign = TRUE, warnings = FALSE)
    usdtry_df <- data.frame(Date = as.character(index(`USDTRY=X`)), USDTRY = as.numeric(Cl(`USDTRY=X`)))
  }, error = function(e) { usdtry_df <<- data.frame(Date = character(0), USDTRY = numeric(0)) })
  tryCatch({
    getSymbols("CL=F", from = "2018-01-01", to = "2026-03-31", auto.assign = TRUE, warnings = FALSE)
    oil_df <- data.frame(Date = as.character(index(`CL=F`)), Oil = as.numeric(Cl(`CL=F`)))
  }, error = function(e) { oil_df <<- data.frame(Date = character(0), Oil = numeric(0)) })
  tryCatch({
    getSymbols("INTDSRTRM193N", src = "FRED", from = "2018-01-01", to = "2026-03-31", auto.assign = TRUE, warnings = FALSE)
    tcmb_df <- data.frame(Date = as.Date(index(INTDSRTRM193N)), TCMB_Rate = as.numeric(INTDSRTRM193N))
    tcmb_daily <- data.frame(Date = as.Date(df$Date)) %>%
      mutate(YearMonth = format(Date, "%Y-%m")) %>%
      left_join(tcmb_df %>% mutate(YearMonth = format(Date, "%Y-%m")), by = "YearMonth") %>%
      select(Date = Date.x, TCMB_Rate)
  }, error = function(e) { tcmb_daily <<- data.frame(Date = as.Date(df$Date), TCMB_Rate = NA_real_) })
  
  df_final <- df %>%
    left_join(usdtry_df, by = "Date") %>%
    left_join(oil_df, by = "Date") %>%
    left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")
  
  df_final$USDTRY <- zoo::na.locf(df_final$USDTRY, na.rm = FALSE)
  df_final$Oil <- zoo::na.locf(df_final$Oil, na.rm = FALSE)
  df_final$TCMB_Rate <- zoo::na.locf(df_final$TCMB_Rate, na.rm = FALSE)
  df_final <- df_final[28:nrow(df_final), ] %>% drop_na()

  IN_LEN <- 2L; OUT_LEN <- 3L
  feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26","SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
  F_DIM <- length(feat_cols)
  feats <- as.matrix(df_final[, feat_cols])
  prices <- df_final$Close; N <- nrow(feats)

  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN+1):(N-OUT_LEN)) {
    X_list[[length(X_list)+1L]] <- feats[(t-IN_LEN+1L):t,, drop=FALSE]
    y_vec <- c(y_vec, as.integer(prices[t+OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim=c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec
  n_total <- length(y_arr)

  i_tr <- floor(n_total*0.70); i_va <- floor(n_total*0.85)
  X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+1L):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
  X_te <- X_arr[(i_va+1L):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+1L):n_total]

  mu_a <- apply(X_tr, c(2,3), mean); sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  norm_fn <- function(A) sweep(sweep(A, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_tr <- norm_fn(X_tr); X_va <- norm_fn(X_va); X_te <- norm_fn(X_te)

  n0 <- sum(y_tr==0); n1 <- sum(y_tr==1); nt <- length(y_tr)
  w0 <- nt/(2*n0); w1 <- nt/(2*n1)
  cw <- list("0"=w0, "1"=w1)
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  for (lam in LAMBDAS) {
    for (sd_seed in SEEDS) {
      cat(sprintf("\n  Hisse: %s | lambda=%.2f seed=%d ...\n", ticker, lam, sd_seed))
      
      keras3::clear_session()
      
      tryCatch({
        model <- build_bilstm(sd_seed, lam, IN_LEN, F_DIM)
        cb <- keras3::callback_early_stopping(monitor = "val_accuracy", patience = 5L, restore_best_weights = TRUE)
        
        model %>% keras3::fit(X_tr, y_tr, validation_data = list(X_va, y_va),
                              epochs = 50L, batch_size = 32L, verbose = 0L,
                              callbacks = list(cb), class_weight = cw)
        
        yhat_val  <- as.numeric(predict(model, X_va, verbose = 0L))
        yhat_test <- as.numeric(predict(model, X_te, verbose = 0L))
        
        # Stats
        global_yhat_stats[[length(global_yhat_stats) + 1]] <<- data.frame(
          ticker = ticker, lambda = lam, seed = sd_seed,
          val_min = min(yhat_val), val_max = max(yhat_val), val_mean = mean(yhat_val), val_sd = stats::sd(yhat_val),
          test_min = min(yhat_test), test_max = max(yhat_test), test_mean = mean(yhat_test), test_sd = stats::sd(yhat_test),
          test_range = max(yhat_test) - min(yhat_test), stringsAsFactors = FALSE
        )

        # Predictions (TEST ONLY for memory efficiency on 11 stocks)
        for (i in seq_along(y_te)) {
          global_predictions[[length(global_predictions) + 1]] <<- data.frame(
            ticker = ticker, lambda = lam, seed = sd_seed, set = "test",
            sample_id = i, yhat = yhat_test[i], y_true = y_te[i], stringsAsFactors = FALSE
          )
        }

        # Thresholds
        for (thr in THRESHOLDS) {
          m_val  <- compute_metrics(y_va, yhat_val, thr)
          m_test <- compute_metrics(y_te, yhat_test, thr)
          global_threshold_rows[[length(global_threshold_rows) + 1]] <<- data.frame(
            ticker = ticker, lambda = lam, seed = sd_seed, threshold = thr,
            Acc_val = m_val$Acc, BalAcc_val = m_val$BalAcc, F1_val = m_val$F1, Sens_val = m_val$Sens, Spec_val = m_val$Spec,
            Acc_test = m_test$Acc, BalAcc_test = m_test$BalAcc, F1_test = m_test$F1, Sens_test = m_test$Sens, Spec_test = m_test$Spec,
            Acc_flip_test = m_test$Acc_flip, is_MC_test = m_test$is_MC, stringsAsFactors = FALSE
          )
        }

        # Optimal
        val_bacc <- sapply(THRESHOLDS, function(thr) {
          m <- compute_metrics(y_va, yhat_val, thr)
          if (is.na(m$BalAcc)) -Inf else m$BalAcc
        })
        best_thr <- THRESHOLDS[which.max(val_bacc)]
        m_val_best  <- compute_metrics(y_va, yhat_val, best_thr)
        m_test_best <- compute_metrics(y_te, yhat_test, best_thr)
        m_test_05   <- compute_metrics(y_te, yhat_test, 0.5)

        global_optimal_rows[[length(global_optimal_rows) + 1]] <<- data.frame(
          ticker = ticker, lambda = lam, seed = sd_seed, best_thr = best_thr,
          val_BalAcc = m_val_best$BalAcc, val_Acc = m_val_best$Acc, naive_acc = naive_acc,
          test_Acc_05 = m_test_05$Acc, test_Spec_05 = m_test_05$Spec, test_Sens_05 = m_test_05$Sens, 
          test_BalAcc_05 = m_test_05$BalAcc, test_F1_05 = m_test_05$F1,
          test_Acc_flip_05 = m_test_05$Acc_flip, test_flip_beats_naive_05 = m_test_05$Acc_flip > naive_acc,
          test_is_MC_05 = m_test_05$is_MC,
          test_Acc_opt = m_test_best$Acc, test_Spec_opt = m_test_best$Spec, test_Sens_opt = m_test_best$Sens, 
          test_BalAcc_opt = m_test_best$BalAcc, test_F1_opt = m_test_best$F1, test_is_MC_opt = m_test_best$is_MC,
          stringsAsFactors = FALSE
        )
      }, error=function(e) {
        cat("  seed=", sd_seed, " HATA:", conditionMessage(e), "\n")
      })
    }
  }
}

# --- Ana çalıştırma ---
TICKERS <- c("THYAO.IS", "PGSUS.IS", "SASA.IS", "TAVHL.IS", "HEKTS.IS", "FROTO.IS", "DOAS.IS", "KOZAL.IS", "KRDMD.IS", "ISCTR.IS", "YKBNK.IS")

t0 <- Sys.time()
for (tk in TICKERS) {
  test_stock(tk)
}
t1 <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dakika\n", as.numeric(difftime(t1, t0, units = "mins"))))

# --- Kayit (5 CSV) ---
df_pred <- do.call(rbind, global_predictions)
df_thr  <- do.call(rbind, global_threshold_rows)
df_opt  <- do.call(rbind, global_optimal_rows)
df_stat <- do.call(rbind, global_yhat_stats)

out1 <- file.path(OUTDIR_PRED, "mcaware_bist_ALL_macro_PREDICTIONS.csv")
out2 <- file.path(OUTDIR_THR, "mcaware_bist_ALL_macro_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR_SUM, "mcaware_bist_ALL_macro_OPTIMAL.csv")
out5 <- file.path(OUTDIR_DIAG, "mcaware_bist_ALL_macro_YHAT_STATS.csv")
out4 <- file.path(OUTDIR_SUM, "mcaware_bist_ALL_macro_SUMMARY.csv")

if(length(df_pred)>0) write.csv(df_pred, out1, row.names = FALSE)
if(length(df_thr)>0) write.csv(df_thr, out2, row.names = FALSE)
if(length(df_opt)>0) write.csv(df_opt, out3, row.names = FALSE)
if(length(df_stat)>0) write.csv(df_stat, out5, row.names = FALSE)

if(length(df_opt)>0) {
  summary_df <- df_opt %>%
    group_by(ticker) %>%
    summarise(
      n_runs = n(),
      naive = mean(naive_acc, na.rm=TRUE),
      mean_best_thr = mean(best_thr, na.rm=TRUE),
      Acc_05 = mean(test_Acc_05, na.rm=TRUE),
      BalAcc_05 = mean(test_BalAcc_05, na.rm=TRUE),
      Acc_flip_05 = mean(test_Acc_flip_05, na.rm=TRUE),
      flip_wins_05 = sum(test_flip_beats_naive_05, na.rm=TRUE),
      MC_05_count = sum(test_is_MC_05, na.rm=TRUE),
      Acc_opt = mean(test_Acc_opt, na.rm=TRUE),
      BalAcc_opt = mean(test_BalAcc_opt, na.rm=TRUE),
      MC_opt_count = sum(test_is_MC_opt, na.rm=TRUE),
      .groups = "drop"
    )
  print(summary_df)
  write.csv(summary_df, out4, row.names = FALSE)
}

cat("\n5 CSV kaydedildi:\n")
cat("  ", out1, "\n  ", out2, "\n  ", out3, "\n  ", out4, "\n  ", out5, "\n", sep = "")
cat("\nTEST TAMAMLANDI.\n")

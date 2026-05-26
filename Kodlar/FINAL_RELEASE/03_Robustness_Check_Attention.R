# ===========================================================================
# MC-AWARE — BIST-5 SIGORTA "ATTENTION" ROBUSTNESS TESTI
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   Sigorta sektöründe görülen "anti-prediktif" (ters sinyal) hatasinin,
#   modelin "hafiza+odak" (Attention) mekanizmasina sahip olmamasiyla mi
#   ilgili oldugunu test etmek. (Dayaniklilik / Robustness Check).
#   MIMARI: BiLSTM (return_sequences=TRUE) + Multi-Head Attention + GlobalPool
#   Kullanilan Hisseler: TURSG.IS, AKGRT.IS, RAYSG.IS, ANSGR.IS, AGESA.IS
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- here::here()
OUTDIR <- here::here("Sonuclar", "summaries")
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(keras3)
  library(quantmod)
  library(rpart)
})

cat("\n========================================================================\n")
cat("MC-AWARE — BIST-5 SIGORTA (ATTENTION ROBUSTNESS TESTI)\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) { dir.create(OUTDIR, recursive = TRUE) }

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
    if (lambda_mc > 0) { bce + lambda_mc * keras3::op_abs(keras3::op_mean(y_pred) - 0.5)
    } else { bce }
  }
}

compute_metrics <- function(y_true, yhat, threshold=0.5) {
  pred <- as.integer(yhat > threshold)
  tp <- sum(pred==1 & y_true==1); tn <- sum(pred==0 & y_true==0)
  fp <- sum(pred==1 & y_true==0); fn <- sum(pred==0 & y_true==1)
  n <- length(y_true); acc <- (tp+tn)/n
  sens <- if ((tp+fn)>0) tp/(tp+fn) else NA_real_
  spec <- if ((tn+fp)>0) tn/(tn+fp) else NA_real_
  is_mc <- isTRUE(spec==0)||isTRUE(sens==0)||is.na(spec)||is.na(sens)
  list(Acc=acc, Sens=sens, Spec=spec, is_MC=is_mc, Acc_flip=1-acc)
}

test_stock <- function(ticker, from="2020-01-01", to="2026-03-31") {
  cat(sprintf("\n--- HISSE: %s (ATTENTION) ---\n", ticker))
  tryCatch({
    getSymbols(ticker, from=from, to=to, auto.assign=TRUE, warnings=FALSE)
    xts_data <- get(gsub("[=]", "", ticker))
  }, error=function(e) { cat("HATA:\n"); return(NULL) })

  df <- data.frame(
    Date=as.character(index(xts_data)),
    Open=as.numeric(Op(xts_data)), High=as.numeric(Hi(xts_data)),
    Low=as.numeric(Lo(xts_data)), Close=as.numeric(Cl(xts_data)),
    Volume=as.numeric(Vo(xts_data)))
  df <- df[df$Volume > 0 & complete.cases(df[,c("Open","High","Low","Close")]), ]
  
  if (nrow(df) < 200) return(NULL)

  df$RSI <- TTR::RSI(df$Close, n=14)
  df$MACD <- TTR::MACD(df$Close)[,"macd"]
  df$EMA12 <- TTR::EMA(df$Close, n=12); df$EMA26 <- TTR::EMA(df$Close, n=26)
  stoch_v <- TTR::stoch(df[,c("High","Low","Close")])
  df$SO_K <- stoch_v[,"fastK"]; df$SO_D <- stoch_v[,"fastD"]
  df$ADX <- TTR::ADX(df[,c("High","Low","Close")])[,"ADX"]
  df <- df[28:nrow(df), ] %>% drop_na()

  IN_LEN <- 2L; OUT_LEN <- 3L
  feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26","SO_K","SO_D","ADX")
  F_DIM <- length(feat_cols)
  feats <- as.matrix(df[, feat_cols])
  prices <- df$Close; N <- nrow(feats)

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
  X_va <- X_arr[(i_tr+OUT_LEN):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+OUT_LEN):i_va]
  X_te <- X_arr[(i_va+OUT_LEN):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+OUT_LEN):n_total]
  
  mu_a <- apply(X_tr, c(2,3), mean); sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  norm_fn <- function(A) sweep(sweep(A, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_tr_norm <- norm_fn(X_tr); X_va_norm <- norm_fn(X_va); X_te_norm <- norm_fn(X_te)

  n0 <- sum(y_tr==0); n1 <- sum(y_tr==1); nt <- length(y_tr)
  w0 <- nt/(2*n0); w1 <- nt/(2*n1); cw <- list("0"=w0, "1"=w1)
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  SEEDS <- c(23L, 42L, 98L)
  results <- list()

  for (sd in SEEDS) {
    keras3::clear_session()
    keras3::set_random_seed(sd)
    
    # ATTENTION MIMARISI (FUNCTIONAL API)
    in_tensor <- keras3::layer_input(shape = c(IN_LEN, F_DIM))
    inner_lstm <- keras3::layer_lstm(units=64, activation="tanh", return_sequences=TRUE)
    lstm_out <- bidir_fn(in_tensor, inner_lstm, merge_mode="concat")
    
    # 2-Head Self Attention
    attn_out <- keras3::layer_multi_head_attention(
      num_heads=2L, key_dim=32L
    )(lstm_out, lstm_out)
    
    # LayerNorm ve Residual 
    add_out <- keras3::layer_add(list(lstm_out, attn_out))
    norm_out <- keras3::layer_layer_normalization()(add_out)
    
    pool_out <- keras3::layer_global_average_pooling_1d()(norm_out)
    pool_drop <- keras3::layer_dropout(pool_out, rate=0.4)
    out_tensor <- keras3::layer_dense(pool_drop, units=1, activation="sigmoid")
    
    model <- keras3::keras_model(inputs=in_tensor, outputs=out_tensor)
    
    model %>% keras3::compile(optimizer=keras3::optimizer_adam(),
                              loss=make_mc_loss(0), metrics=c("accuracy"))
    
    cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L, restore_best_weights=TRUE)
    
    tryCatch({
      model %>% keras3::fit(X_tr_norm, y_tr, validation_data=list(X_va_norm, y_va),
                            epochs=50L, batch_size=32L, verbose=0L,
                            callbacks=list(cb), class_weight=cw)
                            
      yhat <- as.numeric(predict(model, X_te_norm, verbose=0L))
      m <- compute_metrics(y_te, yhat, 0.5)
      
      cat(sprintf("  [BiLSTM+Attn] seed=%d: Acc=%.3f flip=%.3f naive=%.3f\n", sd, m$Acc, m$Acc_flip, naive_acc))
      
      results[[length(results)+1]] <- data.frame(
        ticker=ticker, model="BiLSTM+Attn", seed=sd, acc=m$Acc, acc_flip=m$Acc_flip,
        naive_acc=naive_acc, flip_beats=m$Acc_flip > naive_acc, is_MC=m$is_MC, stringsAsFactors=FALSE)
    }, error=function(e) cat(" HATA:", conditionMessage(e), "\n"))
  }
  do.call(rbind, results)
}

TICKERS <- c("TURSG.IS", "AKGRT.IS", "RAYSG.IS", "ANSGR.IS", "AGESA.IS")
all_res <- list()
for (tk in TICKERS) {
  res <- test_stock(tk)
  if (!is.null(res)) all_res[[length(all_res)+1]] <- res
}

if(length(all_res) > 0) {
  all_df <- do.call(rbind, all_res)
  write.csv(all_df, file.path(OUTDIR, "mcaware_bist5_sigorta_attention_RESULTS.csv"), row.names=FALSE)
  summ_df <- all_df %>% group_by(ticker) %>%
    summarise(mean_acc=mean(acc), mean_flip=mean(acc_flip), naive=mean(naive_acc),
              dl_anti_prediktif_mi = mean(acc_flip) > mean(naive_acc),
              mc_tuzagi_var_mi = any(is_MC), .groups="drop")
  print(summ_df)
  write.csv(summ_df, file.path(OUTDIR, "mcaware_bist5_sigorta_attention_SUMMARY.csv"), row.names=FALSE)
  cat("\nSonuclar kaydedildi!\n")
}

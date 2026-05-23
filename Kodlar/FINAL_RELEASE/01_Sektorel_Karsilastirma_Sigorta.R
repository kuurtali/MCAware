# ===========================================================================
# MC-AWARE — BIST-5 SIGORTA PORTFOYU TESTI (Y5 HİPOTEZİ DOĞRULAMASI)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   Y5 Hipotezini (DL makro-hassas varlıklarda anti-prediktif olur) 
#   THYAO/GARAN dışındaki yepyeni bir homojen sektörde test etmek.
#   Sigorta sektörü faiz ve kur hassasiyeti en yüksek sektördür.
#
#   Kullanılan Hisseler: TURSG.IS, AKGRT.IS, ANSGR.IS, RAYSG.IS, AGESA.IS
#   Klasik ML Baseline olarak Decision Tree ve Logistic Regression da dahil.
#
# VERİ KURALI: Veriler (CSV'ler) quantmod ile internetten çekilir, lokal
# CSV'lere kod tarafından DOKUNULMAZ.
#
# CIKTI: mcaware_bist5_sigorta_SUMMARY.csv
# Süre: ~45-60 dk
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
  library(quantmod)
  library(rpart)
})

cat("\n========================================================================\n")
cat("MC-AWARE — BIST-5 SIGORTA PORTFOYU TESTI\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Hisseler: TURSG.IS, AKGRT.IS, ANSGR.IS, RAYSG.IS, AGESA.IS\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) { dir.create(OUTDIR, recursive = TRUE) }

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

# --- Ana fonksiyon: Tek hisse test ---
test_stock <- function(ticker, from="2020-01-01", to="2026-03-31") {
  cat(sprintf("\n%s\n", strrep("=", 80)))
  cat(sprintf("HISSE: %s\n", ticker))
  cat(sprintf("%s\n", strrep("=", 80)))

  tryCatch({
    getSymbols(ticker, from=from, to=to, auto.assign=TRUE, warnings=FALSE)
    xts_data <- get(gsub("[=]", "", ticker))
  }, error=function(e) {
    cat("HATA: Veri cekilemedi:", conditionMessage(e), "\n")
    return(NULL)
  })

  df <- data.frame(
    Date=as.character(index(xts_data)),
    Open=as.numeric(Op(xts_data)), High=as.numeric(Hi(xts_data)),
    Low=as.numeric(Lo(xts_data)), Close=as.numeric(Cl(xts_data)),
    Volume=as.numeric(Vo(xts_data)))
  df <- df[df$Volume > 0 & complete.cases(df[,c("Open","High","Low","Close")]), ]

  if (nrow(df) < 200) {
    cat(sprintf("YETERSIZ VERI: %d satir\n", nrow(df)))
    return(data.frame(ticker=ticker, n_data=nrow(df), error="yetersiz_veri", stringsAsFactors=FALSE))
  }

  # Teknik göstergeler
  df$RSI <- TTR::RSI(df$Close, n=14)
  macd_v <- TTR::MACD(df$Close); df$MACD <- macd_v[,"macd"]
  df$EMA12 <- TTR::EMA(df$Close, n=12); df$EMA26 <- TTR::EMA(df$Close, n=26)
  stoch_v <- TTR::stoch(df[,c("High","Low","Close")])
  df$SO_K <- stoch_v[,"fastK"]; df$SO_D <- stoch_v[,"fastD"]
  adx_v <- TTR::ADX(df[,c("High","Low","Close")]); df$ADX <- adx_v[,"ADX"]
  df <- df[28:nrow(df), ] %>% drop_na()
  cat(sprintf("  Temiz veri: %d satir\n", nrow(df)))

  # Pencereleme
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

  # Split
  i_tr <- floor(n_total*0.70); i_va <- floor(n_total*0.85)
  X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+OUT_LEN):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+OUT_LEN):i_va]
  X_te <- X_arr[(i_va+OUT_LEN):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+OUT_LEN):n_total]
  
  # ML Data (Flattened)
  X_tr_flat <- t(apply(X_tr, 1, c))
  X_te_flat <- t(apply(X_te, 1, c))
  
  cat(sprintf("  Split: Tr=%d Va=%d Te=%d | Up%%: Tr=%.1f Te=%.1f\n",
              length(y_tr), length(y_va), length(y_te),
              100*mean(y_tr), 100*mean(y_te)))

  # Normalize (DL için)
  mu_a <- apply(X_tr, c(2,3), mean); sd_a <- apply(X_tr, c(2,3), stats::sd) + 1e-8
  norm_fn <- function(A) sweep(sweep(A, c(2,3), mu_a, "-"), c(2,3), sd_a, "/")
  X_tr_norm <- norm_fn(X_tr); X_va_norm <- norm_fn(X_va); X_te_norm <- norm_fn(X_te)

  # CW
  n0 <- sum(y_tr==0); n1 <- sum(y_tr==1); nt <- length(y_tr)
  w0 <- nt/(2*n0); w1 <- nt/(2*n1)
  cw <- list("0"=w0, "1"=w1)
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  # Klasik ML (Decision Tree)
  p0 <- w0 / (w0 + w1)
  p1 <- 1.0 - p0
  dt_model <- rpart(y ~ ., data=data.frame(y=y_tr, X_tr_flat), method="class", 
                    parms=list(prior=c(p0, p1)))
  dt_pred <- predict(dt_model, data.frame(X_te_flat), type="class")
  dt_acc <- mean(as.numeric(as.character(dt_pred)) == y_te)
  cat(sprintf("  [Klasik ML] Decision Tree Acc: %.3f (Naive: %.3f) - Beats Naive: %s\n", 
              dt_acc, naive_acc, dt_acc > naive_acc))

  # DL GRID: 3 seed x 1 lambda
  SEEDS <- c(23L, 42L, 98L)
  results <- list()

  for (sd in SEEDS) {
    keras3::clear_session()
    tryCatch({
      keras3::set_random_seed(sd)
      inner <- keras3::layer_lstm(units=64, activation="tanh", return_sequences=FALSE)
      model <- keras3::keras_model_sequential(input_shape=c(IN_LEN, F_DIM))
      model <- bidir_fn(model, inner, merge_mode="concat")
      model <- model %>%
        keras3::layer_dropout(rate=0.4) %>%
        keras3::layer_dense(units=1, activation="sigmoid")
      
      model %>% keras3::compile(optimizer=keras3::optimizer_adam(),
                                loss=make_mc_loss(0), metrics=c("accuracy"))
      cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L,
                                             restore_best_weights=TRUE)
      model %>% keras3::fit(X_tr_norm, y_tr, validation_data=list(X_va_norm, y_va),
                            epochs=50L, batch_size=32L, verbose=0L,
                            callbacks=list(cb), class_weight=cw)
      yhat <- as.numeric(predict(model, X_te_norm, verbose=0L))
      m <- compute_metrics(y_te, yhat, 0.5)
      
      cat(sprintf("  [DL] seed=%d: Acc=%.3f flip=%.3f naive=%.3f flip_beats=%s MC=%s\n",
                  sd, m$Acc, m$Acc_flip, naive_acc,
                  m$Acc_flip > naive_acc, m$is_MC))
      
      results[[length(results)+1]] <- data.frame(
        ticker=ticker, model="BiLSTM", seed=sd, acc=m$Acc, acc_flip=m$Acc_flip,
        naive_acc=naive_acc, dt_acc=dt_acc, flip_beats=m$Acc_flip > naive_acc,
        is_MC=m$is_MC, stringsAsFactors=FALSE)
    }, error=function(e) {
      cat("  seed=", sd, " HATA:", conditionMessage(e), "\n")
    })
  }
  do.call(rbind, results)
}

# --- Ana çalıştırma ---
TICKERS <- c("TURSG.IS", "AKGRT.IS", "ANSGR.IS", "RAYSG.IS", "AGESA.IS")
all_results <- list()

for (tk in TICKERS) {
  res <- test_stock(tk)
  if (!is.null(res)) all_results[[length(all_results)+1]] <- res
}

if(length(all_results) > 0) {
  all_df <- do.call(rbind, all_results)
  write.csv(all_df, file.path(OUTDIR, "mcaware_bist5_sigorta_RESULTS.csv"), row.names=FALSE)

  # Özet
  cat("\n", strrep("=", 80), "\n", sep="")
  cat("ADIM I.19 — BIST-5 SIGORTA SONUCLARI\n")
  cat(strrep("=", 80), "\n", sep="")

  summary_df <- all_df %>%
    group_by(ticker) %>%
    summarise(mean_acc=mean(acc, na.rm=TRUE),
              mean_flip=mean(acc_flip, na.rm=TRUE),
              naive=mean(naive_acc),
              dt_acc=mean(dt_acc),
              dl_anti_prediktif_mi = mean(acc_flip) > mean(naive_acc),
              .groups="drop")
  print(summary_df)

  write.csv(summary_df, file.path(OUTDIR, "mcaware_bist5_sigorta_SUMMARY.csv"), row.names=FALSE)
  cat(sprintf("\nDosyalar Sonuclar klasorune kaydedildi.\n"))
} else {
  cat("\nHicbir hisse basariyla cekilemedi/test edilemedi.\n")
}
cat("\nBIST-5 SIGORTA TESTI TAMAMLANDI.\n")

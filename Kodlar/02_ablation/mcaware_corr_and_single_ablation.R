# ===========================================================================
# MC-AWARE — KORELASYON KIRILMASI ANALİZİ (ADIM I.12)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   I.11 mekanizmayı belirledi: dış değişkenler (USDTRY, Oil, TCMB)
#   anti-prediktif davranışın kaynağı.
#   HİPOTEZ: Train döneminde korelasyon yapısı farklı, test döneminde
#   kırılmış. Model eski korelasyonu öğrenip test'te ters tahmin yapıyor.
#
# İKİ ANALİZ:
#   (A) Train vs Test korelasyon matrisi (Pearson)
#   (B) Tek tek makro değişken ablation:
#       - 13 feat (full) — referans
#       - 12 feat (USDTRY hariç)
#       - 12 feat (Oil hariç)
#       - 12 feat (TCMB hariç)
#       → Hangisi çıkarılınca anti-prediktif kayboluyor?
#
# CIKTI: mcaware_corr_analysis.csv + mcaware_single_feat_ablation.csv
# Süre: ~45-60 dk
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
cat("MC-AWARE — KORELASYON KIRILMASI + TEK DEGISKEN ABLATION (ADIM I.12)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- THYAO veri (ayni pipeline) ---
cat("THYAO verisi cekiliyor...\n")
getSymbols("THYAO.IS", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
thyao_xts <- THYAO.IS
thyao_df <- data.frame(
  Date=as.character(index(thyao_xts)),
  Open=as.numeric(Op(thyao_xts)), High=as.numeric(Hi(thyao_xts)),
  Low=as.numeric(Lo(thyao_xts)), Close=as.numeric(Cl(thyao_xts)),
  Volume=as.numeric(Vo(thyao_xts)))
thyao_df <- thyao_df[thyao_df$Volume > 0 & complete.cases(thyao_df[,c("Open","High","Low","Close")]), ]
thyao_df$RSI <- TTR::RSI(thyao_df$Close, n=14)
macd_v <- TTR::MACD(thyao_df$Close); thyao_df$MACD <- macd_v[,"macd"]
thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n=12)
thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n=26)
stoch_v <- TTR::stoch(thyao_df[,c("High","Low","Close")])
thyao_df$SO_K <- stoch_v[,"fastK"]; thyao_df$SO_D <- stoch_v[,"fastD"]
adx_v <- TTR::ADX(thyao_df[,c("High","Low","Close")]); thyao_df$ADX <- adx_v[,"ADX"]

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
N <- nrow(thyao_final)

# ═══ BOLUM A: KORELASYON KIRILMASI ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BOLUM A: TRAIN vs TEST KORELASYON ANALIZI\n")
cat(strrep("=", 80), "\n", sep="")

i_split <- floor(N * 0.70)
train_data <- thyao_final[1:i_split, ]
test_data  <- thyao_final[(i_split+1):N, ]

macro_vars <- c("USDTRY", "Oil", "TCMB_Rate")
target_var <- "Close"

corr_rows <- list()
for (mv in macro_vars) {
  cor_train <- cor(train_data[[target_var]], train_data[[mv]], use="complete.obs")
  cor_test  <- cor(test_data[[target_var]], test_data[[mv]], use="complete.obs")
  cor_diff  <- cor_test - cor_train
  # Log-return korelasyonu da bak
  tr_ret <- diff(log(train_data[[target_var]])); tr_mv_ret <- diff(log(train_data[[mv]]))
  te_ret <- diff(log(test_data[[target_var]])); te_mv_ret <- diff(log(test_data[[mv]]))
  cor_train_ret <- cor(tr_ret, tr_mv_ret, use="complete.obs")
  cor_test_ret  <- cor(te_ret, te_mv_ret, use="complete.obs")

  cat(sprintf("\n  %s:\n", mv))
  cat(sprintf("    Fiyat korelasyonu:  Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train, cor_test, cor_diff))
  cat(sprintf("    Return korelasyonu: Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train_ret, cor_test_ret, cor_test_ret - cor_train_ret))

  corr_rows[[length(corr_rows)+1]] <- data.frame(
    variable=mv, metric="price_level",
    cor_train=cor_train, cor_test=cor_test, cor_diff=cor_diff,
    stringsAsFactors=FALSE)
  corr_rows[[length(corr_rows)+1]] <- data.frame(
    variable=mv, metric="log_return",
    cor_train=cor_train_ret, cor_test=cor_test_ret, cor_diff=cor_test_ret-cor_train_ret,
    stringsAsFactors=FALSE)
}

corr_df <- do.call(rbind, corr_rows)
write.csv(corr_df, file.path(OUTDIR_DIAG, "mcaware_corr_analysis.csv"), row.names=FALSE)
cat("\n\nKorelasyon CSV kaydedildi.\n")

# ═══ BOLUM B: TEK TEK MAKRO DEGISKEN ABLATION ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BOLUM B: TEK DEGISKEN ABLATION (hangisi suclu?)\n")
cat(strrep("=", 80), "\n", sep="")

IN_LEN <- 2L; OUT_LEN <- 3L
prices <- thyao_final$Close

FEAT_GROUPS <- list(
  full_13      = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                   "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate"),
  no_USDTRY_12 = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                    "SO_K","SO_D","ADX","Oil","TCMB_Rate"),
  no_Oil_12    = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                   "SO_K","SO_D","ADX","USDTRY","TCMB_Rate"),
  no_TCMB_12   = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                    "SO_K","SO_D","ADX","USDTRY","Oil"),
  no_ext_10    = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                   "SO_K","SO_D","ADX")
)

make_mc_loss <- function(lmc=0) {
  function(yt, yp_) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp <- keras3::op_clip(yp_, eps, one-eps)
    bce <- -(yt*keras3::op_log(yp)+(one-yt)*keras3::op_log(one-yp))
    if (lmc>0) bce+lmc*keras3::op_abs(keras3::op_mean(yp_)-0.5) else bce
  }
}

SEEDS <- c(23L, 42L, 98L)  # 3 seed hızlı sonuc icin
all_results <- list()
t0 <- Sys.time()

for (grp_name in names(FEAT_GROUPS)) {
  fc <- FEAT_GROUPS[[grp_name]]
  F_DIM <- length(fc)
  feats <- as.matrix(thyao_final[, fc])

  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN+1):(N-OUT_LEN)) {
    X_list[[length(X_list)+1L]] <- feats[(t-IN_LEN+1L):t,, drop=FALSE]
    y_vec <- c(y_vec, as.integer(prices[t+OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim=c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec; n_total <- length(y_arr)
  i_tr <- floor(n_total*0.70); i_va <- floor(n_total*0.85)
  X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+1L):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
  X_te <- X_arr[(i_va+1L):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+1L):n_total]

  mu_a <- apply(X_tr,c(2,3),mean); sd_a <- apply(X_tr,c(2,3),stats::sd)+1e-8
  nf <- function(A) sweep(sweep(A,c(2,3),mu_a,"-"),c(2,3),sd_a,"/")
  X_tr <- nf(X_tr); X_va <- nf(X_va); X_te <- nf(X_te)
  n0 <- sum(y_tr==0); n1 <- sum(y_tr==1); nt <- length(y_tr)
  cw <- list("0"=nt/(2*n0), "1"=nt/(2*n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  cat(sprintf("\n--- %s (%d feat) ---\n", grp_name, F_DIM))

  for (sd in SEEDS) {
    keras3::clear_session()
    tryCatch({
      keras3::set_random_seed(sd)
      inner <- keras3::layer_lstm(units=64, activation="tanh", return_sequences=FALSE)
      model <- keras3::keras_model_sequential(input_shape=c(IN_LEN, F_DIM))
      model <- bidir_fn(model, inner, merge_mode="concat")
      model <- model %>% keras3::layer_dropout(rate=0.4) %>%
        keras3::layer_dense(units=1, activation="sigmoid")
      model %>% keras3::compile(optimizer=keras3::optimizer_adam(),
                                loss=make_mc_loss(0), metrics=c("accuracy"))
      cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L,
                                             restore_best_weights=TRUE)
      model %>% keras3::fit(X_tr, y_tr, validation_data=list(X_va, y_va),
                            epochs=50L, batch_size=32L, verbose=0L,
                            callbacks=list(cb), class_weight=cw)
      yhat <- as.numeric(predict(model, X_te, verbose=0L))
      acc <- mean((yhat>0.5)==y_te); flip <- 1-acc
      cat(sprintf("  sd=%d: Acc=%.3f flip=%.3f beats=%s\n",
                  sd, acc, flip, flip>naive_acc))
      all_results[[length(all_results)+1]] <- data.frame(
        group=grp_name, n_feat=F_DIM, seed=sd, acc=acc, acc_flip=flip,
        naive=naive_acc, flip_beats=flip>naive_acc, stringsAsFactors=FALSE)
    }, error=function(e) {
      cat("  HATA:", conditionMessage(e), "\n")
      all_results[[length(all_results)+1]] <<- data.frame(
        group=grp_name, n_feat=F_DIM, seed=sd, acc=NA, acc_flip=NA,
        naive=naive_acc, flip_beats=NA, stringsAsFactors=FALSE)
    })
  }
}

t1 <- Sys.time()
cat(sprintf("\nSure: %.1f dk\n", as.numeric(difftime(t1, t0, units="mins"))))

res_df <- do.call(rbind, all_results)
write.csv(res_df, file.path(OUTDIR_SUM, "mcaware_single_feat_ablation_RESULTS.csv"), row.names=FALSE)

summary_df <- res_df %>% group_by(group, n_feat) %>%
  summarise(n_seed=n(), mean_acc=mean(acc,na.rm=TRUE), mean_flip=mean(acc_flip,na.rm=TRUE),
            flip_wins=sum(flip_beats,na.rm=TRUE), .groups="drop")
write.csv(summary_df, file.path(OUTDIR_SUM, "mcaware_single_feat_ablation_SUMMARY.csv"), row.names=FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.12 — TEK DEGISKEN ABLATION SONUCLARI\n")
cat(strrep("=", 80), "\n", sep="")
print(summary_df)

cat("\nHangisi cikarilinca anti-prediktif KAYBOLUYOR?\n")
for (i in 1:nrow(summary_df)) {
  g <- summary_df$group[i]; fw <- summary_df$flip_wins[i]; ns <- summary_df$n_seed[i]
  status <- if (fw >= 2) "ANTI-PREDIKTIF" else "NOTR"
  cat(sprintf("  %-15s: %d/%d flip_wins → %s\n", g, fw, ns, status))
}

 # ===========================================================================
# MC-AWARE — KORELASYON KIRILMASI ANALİZİ (ADIM I.12)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   I.11 mekanizmayı belirledi: dış değişkenler (USDTRY, Oil, TCMB)
#   anti-prediktif davranışın kaynağı.
#   HİPOTEZ: Train döneminde korelasyon yapısı farklı, test döneminde
#   kırılmış. Model eski korelasyonu öğrenip test'te ters tahmin yapıyor.
#
# İKİ ANALİZ:
#   (A) Train vs Test korelasyon matrisi (Pearson)
#   (B) Tek tek makro değişken ablation:
#       - 13 feat (full) — referans
#       - 12 feat (USDTRY hariç)
#       - 12 feat (Oil hariç)
#       - 12 feat (TCMB hariç)
#       → Hangisi çıkarılınca anti-prediktif kayboluyor?
#
# CIKTI: mcaware_corr_analysis.csv + mcaware_single_feat_ablation.csv
# Süre: ~45-60 dk
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
cat("MC-AWARE — KORELASYON KIRILMASI + TEK DEGISKEN ABLATION (ADIM I.12)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- THYAO veri (ayni pipeline) ---
cat("THYAO verisi cekiliyor...\n")
getSymbols("THYAO.IS", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
thyao_xts <- THYAO.IS
thyao_df <- data.frame(
  Date=as.character(index(thyao_xts)),
  Open=as.numeric(Op(thyao_xts)), High=as.numeric(Hi(thyao_xts)),
  Low=as.numeric(Lo(thyao_xts)), Close=as.numeric(Cl(thyao_xts)),
  Volume=as.numeric(Vo(thyao_xts)))
thyao_df <- thyao_df[thyao_df$Volume > 0 & complete.cases(thyao_df[,c("Open","High","Low","Close")]), ]
thyao_df$RSI <- TTR::RSI(thyao_df$Close, n=14)
macd_v <- TTR::MACD(thyao_df$Close); thyao_df$MACD <- macd_v[,"macd"]
thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n=12)
thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n=26)
stoch_v <- TTR::stoch(thyao_df[,c("High","Low","Close")])
thyao_df$SO_K <- stoch_v[,"fastK"]; thyao_df$SO_D <- stoch_v[,"fastD"]
adx_v <- TTR::ADX(thyao_df[,c("High","Low","Close")]); thyao_df$ADX <- adx_v[,"ADX"]

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
N <- nrow(thyao_final)

# ═══ BOLUM A: KORELASYON KIRILMASI ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BOLUM A: TRAIN vs TEST KORELASYON ANALIZI\n")
cat(strrep("=", 80), "\n", sep="")

i_split <- floor(N * 0.70)
train_data <- thyao_final[1:i_split, ]
test_data  <- thyao_final[(i_split+1):N, ]

macro_vars <- c("USDTRY", "Oil", "TCMB_Rate")
target_var <- "Close"

corr_rows <- list()
for (mv in macro_vars) {
  cor_train <- cor(train_data[[target_var]], train_data[[mv]], use="complete.obs")
  cor_test  <- cor(test_data[[target_var]], test_data[[mv]], use="complete.obs")
  cor_diff  <- cor_test - cor_train
  # Log-return korelasyonu da bak
  tr_ret <- diff(log(train_data[[target_var]])); tr_mv_ret <- diff(log(train_data[[mv]]))
  te_ret <- diff(log(test_data[[target_var]])); te_mv_ret <- diff(log(test_data[[mv]]))
  cor_train_ret <- cor(tr_ret, tr_mv_ret, use="complete.obs")
  cor_test_ret  <- cor(te_ret, te_mv_ret, use="complete.obs")

  cat(sprintf("\n  %s:\n", mv))
  cat(sprintf("    Fiyat korelasyonu:  Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train, cor_test, cor_diff))
  cat(sprintf("    Return korelasyonu: Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train_ret, cor_test_ret, cor_test_ret - cor_train_ret))

  corr_rows[[length(corr_rows)+1]] <- data.frame(
    variable=mv, metric="price_level",
    cor_train=cor_train, cor_test=cor_test, cor_diff=cor_diff,
    stringsAsFactors=FALSE)
  corr_rows[[length(corr_rows)+1]] <- data.frame(
    variable=mv, metric="log_return",
    cor_train=cor_train_ret, cor_test=cor_test_ret, cor_diff=cor_test_ret-cor_train_ret,
    stringsAsFactors=FALSE)
}

corr_df <- do.call(rbind, corr_rows)
write.csv(corr_df, file.path(OUTDIR_DIAG, "mcaware_corr_analysis.csv"), row.names=FALSE)
cat("\n\nKorelasyon CSV kaydedildi.\n")

# ═══ BOLUM B: TEK TEK MAKRO DEGISKEN ABLATION ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BOLUM B: TEK DEGISKEN ABLATION (hangisi suclu?)\n")
cat(strrep("=", 80), "\n", sep="")

IN_LEN <- 2L; OUT_LEN <- 3L
prices <- thyao_final$Close

FEAT_GROUPS <- list(
  full_13      = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                   "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate"),
  no_USDTRY_12 = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                    "SO_K","SO_D","ADX","Oil","TCMB_Rate"),
  no_Oil_12    = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                   "SO_K","SO_D","ADX","USDTRY","TCMB_Rate"),
  no_TCMB_12   = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                    "SO_K","SO_D","ADX","USDTRY","Oil"),
  no_ext_10    = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                   "SO_K","SO_D","ADX")
)

make_mc_loss <- function(lmc=0) {
  function(yt, yp_) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp <- keras3::op_clip(yp_, eps, one-eps)
    bce <- -(yt*keras3::op_log(yp)+(one-yt)*keras3::op_log(one-yp))
    if (lmc>0) bce+lmc*keras3::op_abs(keras3::op_mean(yp_)-0.5) else bce
  }
}

SEEDS <- c(23L, 42L, 98L)  # 3 seed hızlı sonuc icin
all_results <- list()
t0 <- Sys.time()

for (grp_name in names(FEAT_GROUPS)) {
  fc <- FEAT_GROUPS[[grp_name]]
  F_DIM <- length(fc)
  feats <- as.matrix(thyao_final[, fc])

  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN+1):(N-OUT_LEN)) {
    X_list[[length(X_list)+1L]] <- feats[(t-IN_LEN+1L):t,, drop=FALSE]
    y_vec <- c(y_vec, as.integer(prices[t+OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim=c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec; n_total <- length(y_arr)
  i_tr <- floor(n_total*0.70); i_va <- floor(n_total*0.85)
  X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+1L):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
  X_te <- X_arr[(i_va+1L):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+1L):n_total]

  mu_a <- apply(X_tr,c(2,3),mean); sd_a <- apply(X_tr,c(2,3),stats::sd)+1e-8
  nf <- function(A) sweep(sweep(A,c(2,3),mu_a,"-"),c(2,3),sd_a,"/")
  X_tr <- nf(X_tr); X_va <- nf(X_va); X_te <- nf(X_te)
  n0 <- sum(y_tr==0); n1 <- sum(y_tr==1); nt <- length(y_tr)
  cw <- list("0"=nt/(2*n0), "1"=nt/(2*n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  cat(sprintf("\n--- %s (%d feat) ---\n", grp_name, F_DIM))

  for (sd in SEEDS) {
    keras3::clear_session()
    tryCatch({
      keras3::set_random_seed(sd)
      inner <- keras3::layer_lstm(units=64, activation="tanh", return_sequences=FALSE)
      model <- keras3::keras_model_sequential(input_shape=c(IN_LEN, F_DIM))
      model <- bidir_fn(model, inner, merge_mode="concat")
      model <- model %>% keras3::layer_dropout(rate=0.4) %>%
        keras3::layer_dense(units=1, activation="sigmoid")
      model %>% keras3::compile(optimizer=keras3::optimizer_adam(),
                                loss=make_mc_loss(0), metrics=c("accuracy"))
      cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L,
                                             restore_best_weights=TRUE)
      model %>% keras3::fit(X_tr, y_tr, validation_data=list(X_va, y_va),
                            epochs=50L, batch_size=32L, verbose=0L,
                            callbacks=list(cb), class_weight=cw)
      yhat <- as.numeric(predict(model, X_te, verbose=0L))
      acc <- mean((yhat>0.5)==y_te); flip <- 1-acc
      cat(sprintf("  sd=%d: Acc=%.3f flip=%.3f beats=%s\n",
                  sd, acc, flip, flip>naive_acc))
      all_results[[length(all_results)+1]] <- data.frame(
        group=grp_name, n_feat=F_DIM, seed=sd, acc=acc, acc_flip=flip,
        naive=naive_acc, flip_beats=flip>naive_acc, stringsAsFactors=FALSE)
    }, error=function(e) {
      cat("  HATA:", conditionMessage(e), "\n")
      all_results[[length(all_results)+1]] <<- data.frame(
        group=grp_name, n_feat=F_DIM, seed=sd, acc=NA, acc_flip=NA,
        naive=naive_acc, flip_beats=NA, stringsAsFactors=FALSE)
    })
  }
}

t1 <- Sys.time()
cat(sprintf("\nSure: %.1f dk\n", as.numeric(difftime(t1, t0, units="mins"))))

res_df <- do.call(rbind, all_results)
write.csv(res_df, file.path(OUTDIR_SUM, "mcaware_single_feat_ablation_RESULTS.csv"), row.names=FALSE)

summary_df <- res_df %>% group_by(group, n_feat) %>%
  summarise(n_seed=n(), mean_acc=mean(acc,na.rm=TRUE), mean_flip=mean(acc_flip,na.rm=TRUE),
            flip_wins=sum(flip_beats,na.rm=TRUE), .groups="drop")
write.csv(summary_df, file.path(OUTDIR_SUM, "mcaware_single_feat_ablation_SUMMARY.csv"), row.names=FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.12 — TEK DEGISKEN ABLATION SONUCLARI\n")
cat(strrep("=", 80), "\n", sep="")
print(summary_df)

cat("\nHangisi cikarilinca anti-prediktif KAYBOLUYOR?\n")
for (i in 1:nrow(summary_df)) {
  g <- summary_df$group[i]; fw <- summary_df$flip_wins[i]; ns <- summary_df$n_seed[i]
  status <- if (fw >= 2) "ANTI-PREDIKTIF" else "NOTR"
  cat(sprintf("  %-15s: %d/%d flip_wins → %s\n", g, fw, ns, status))
}

cat(sprintf("\nCSV'ler kaydedildi: %s\n", OUTDIR))
cat("\nADIM I.12 TAMAMLANDI.\n")
.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' )
cat("\nADIM I.12 TAMAMLANDI.\n")

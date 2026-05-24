# ===========================================================================
# MC-AWARE — NASDAQ KARSILASTIRMA (ADIM I.13: GELISMIS vs GELISMEKTE)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   THYAO'da korelasyon kırılması → anti-prediktif kanıtlandı.
#   Soru: Bu gelişmekte olan piyasalara mı özgü?
#   Test: AAPL (NASDAQ, en likit ABD hissesi) aynı pipeline ile.
#   Makro değişkenler: DXY (dolar endeksi), Oil, Fed Funds Rate
#
#   Beklenti:
#     Eğer AAPL'de anti-prediktif → evrensel problem
#     Eğer AAPL'de nötr/pozitif → BIST/gelişmekte olan piyasaya özgü
#       (kur krizi, faiz şoku vb. rejim değişimlerinin etkisi)
#
# CIKTI: mcaware_nasdaq_RESULTS.csv + mcaware_nasdaq_CORR.csv
# Süre: ~30-45 dk
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- here::here()
OUTDIR <- here::here()
setwd(WORKDIR)
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")

suppressPackageStartupMessages({
  library(tidyverse); library(TTR); library(zoo)
  library(keras3); library(tensorflow); library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE — NASDAQ KARSILASTIRMA (ADIM I.13)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Hisse: AAPL (NASDAQ) | Makro: DXY, Oil, Fed Rate\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- Veri cekme ---
cat("AAPL verisi cekiliyor...\n")
getSymbols("AAPL", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
aapl_df <- data.frame(
  Date=as.character(index(AAPL)),
  Open=as.numeric(Op(AAPL)), High=as.numeric(Hi(AAPL)),
  Low=as.numeric(Lo(AAPL)), Close=as.numeric(Cl(AAPL)),
  Volume=as.numeric(Vo(AAPL)))
aapl_df <- aapl_df[aapl_df$Volume > 0 & complete.cases(aapl_df[,c("Open","High","Low","Close")]), ]
cat(sprintf("AAPL ham: %d satir\n", nrow(aapl_df)))

# Teknik göstergeler
aapl_df$RSI <- TTR::RSI(aapl_df$Close, n=14)
macd_v <- TTR::MACD(aapl_df$Close); aapl_df$MACD <- macd_v[,"macd"]
aapl_df$EMA12 <- TTR::EMA(aapl_df$Close, n=12)
aapl_df$EMA26 <- TTR::EMA(aapl_df$Close, n=26)
stoch_v <- TTR::stoch(aapl_df[,c("High","Low","Close")])
aapl_df$SO_K <- stoch_v[,"fastK"]; aapl_df$SO_D <- stoch_v[,"fastD"]
adx_v <- TTR::ADX(aapl_df[,c("High","Low","Close")]); aapl_df$ADX <- adx_v[,"ADX"]

# Makro değişkenler (ABD)
cat("ABD makro degiskenleri cekiliyor...\n")
tryCatch({
  getSymbols("DX-Y.NYB", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  dxy_df <- data.frame(Date=as.character(index(`DX-Y.NYB`)),
                        DXY=as.numeric(Cl(`DX-Y.NYB`)))
}, error=function(e) {
  cat("DXY cekilemedi, UUP ETF deneniyor...\n")
  tryCatch({
    getSymbols("UUP", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
    dxy_df <<- data.frame(Date=as.character(index(UUP)), DXY=as.numeric(Cl(UUP)))
  }, error=function(e2) { dxy_df <<- data.frame(Date=character(0), DXY=numeric(0)) })
})
tryCatch({
  getSymbols("CL=F", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  oil_df <- data.frame(Date=as.character(index(`CL=F`)), Oil=as.numeric(Cl(`CL=F`)))
}, error=function(e) { oil_df <<- data.frame(Date=character(0), Oil=numeric(0)) })
tryCatch({
  getSymbols("FEDFUNDS", src="FRED", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  fed_df <- data.frame(Date=as.Date(index(FEDFUNDS)), Fed_Rate=as.numeric(FEDFUNDS))
  fed_daily <- data.frame(Date=as.Date(aapl_df$Date)) %>%
    mutate(YearMonth=format(Date,"%Y-%m")) %>%
    left_join(fed_df %>% mutate(YearMonth=format(Date,"%Y-%m")), by="YearMonth") %>%
    select(Date=Date.x, Fed_Rate)
}, error=function(e) { fed_daily <<- data.frame(Date=as.Date(aapl_df$Date), Fed_Rate=NA_real_) })

aapl_final <- aapl_df %>%
  left_join(dxy_df, by="Date") %>% left_join(oil_df, by="Date") %>%
  left_join(fed_daily %>% mutate(Date=as.character(Date)), by="Date")
aapl_final$DXY <- zoo::na.locf(aapl_final$DXY, na.rm=FALSE)
aapl_final$Oil <- zoo::na.locf(aapl_final$Oil, na.rm=FALSE)
aapl_final$Fed_Rate <- zoo::na.locf(aapl_final$Fed_Rate, na.rm=FALSE)
aapl_final <- aapl_final[28:nrow(aapl_final), ] %>% drop_na()
cat(sprintf("Final AAPL: %d satir\n", nrow(aapl_final)))

# ═══ BOLUM A: KORELASYON ANALIZI ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BOLUM A: AAPL — TRAIN vs TEST KORELASYON\n")
cat(strrep("=", 80), "\n", sep="")

N <- nrow(aapl_final)
i_split <- floor(N * 0.70)
train_d <- aapl_final[1:i_split, ]
test_d  <- aapl_final[(i_split+1):N, ]

macro_vars <- c("DXY", "Oil", "Fed_Rate")
corr_rows <- list()
for (mv in macro_vars) {
  ct <- cor(train_d$Close, train_d[[mv]], use="complete.obs")
  ce <- cor(test_d$Close, test_d[[mv]], use="complete.obs")
  cat(sprintf("  %s: Train=%.3f Test=%.3f FARK=%.3f\n", mv, ct, ce, ce-ct))
  corr_rows[[length(corr_rows)+1]] <- data.frame(
    market="NASDAQ_AAPL", variable=mv, cor_train=ct, cor_test=ce,
    cor_diff=ce-ct, stringsAsFactors=FALSE)
}
# THYAO referans ekle
corr_rows[[length(corr_rows)+1]] <- data.frame(
  market="BIST_THYAO", variable="USDTRY", cor_train=0.908, cor_test=0.412,
  cor_diff=-0.496, stringsAsFactors=FALSE)
corr_rows[[length(corr_rows)+1]] <- data.frame(
  market="BIST_THYAO", variable="Oil", cor_train=0.414, cor_test=-0.148,
  cor_diff=-0.562, stringsAsFactors=FALSE)
corr_rows[[length(corr_rows)+1]] <- data.frame(
  market="BIST_THYAO", variable="TCMB_Rate", cor_train=0.194, cor_test=0.311,
  cor_diff=0.117, stringsAsFactors=FALSE)

corr_all <- do.call(rbind, corr_rows)
write.csv(corr_all, file.path(OUTDIR, "mcaware_nasdaq_CORR.csv"), row.names=FALSE)

# ═══ BOLUM B: AAPL BiLSTM TEST ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BOLUM B: AAPL — BiLSTM (13 feat vs 10 feat)\n")
cat(strrep("=", 80), "\n", sep="")

IN_LEN <- 2L; OUT_LEN <- 3L
prices <- aapl_final$Close

FEAT_GROUPS <- list(
  full_13 = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
              "SO_K","SO_D","ADX","DXY","Oil","Fed_Rate"),
  no_ext_10 = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
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

SEEDS <- c(23L, 42L, 98L)
all_results <- list()
t0 <- Sys.time()

for (grp_name in names(FEAT_GROUPS)) {
  fc <- FEAT_GROUPS[[grp_name]]
  F_DIM <- length(fc)
  feats <- as.matrix(aapl_final[, fc])

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

  cat(sprintf("\n--- %s (%d feat) | Naive=%.3f ---\n", grp_name, F_DIM, naive_acc))

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
      cat(sprintf("  sd=%d: Acc=%.3f flip=%.3f naive=%.3f beats=%s\n",
                  sd, acc, flip, naive_acc, flip>naive_acc))
      all_results[[length(all_results)+1]] <- data.frame(
        market="NASDAQ_AAPL", group=grp_name, n_feat=F_DIM, seed=sd,
        acc=acc, acc_flip=flip, naive=naive_acc,
        flip_beats=flip>naive_acc, stringsAsFactors=FALSE)
    }, error=function(e) {
      cat("  HATA:", conditionMessage(e), "\n")
      all_results[[length(all_results)+1]] <<- data.frame(
        market="NASDAQ_AAPL", group=grp_name, n_feat=F_DIM, seed=sd,
        acc=NA, acc_flip=NA, naive=naive_acc, flip_beats=NA,
        stringsAsFactors=FALSE)
    })
  }
}

t1 <- Sys.time()
res_df <- do.call(rbind, all_results)

# THYAO referans ekle
res_df <- rbind(res_df, data.frame(
  market="BIST_THYAO", group="full_13", n_feat=13, seed=NA,
  acc=0.396, acc_flip=0.604, naive=0.518, flip_beats=TRUE, stringsAsFactors=FALSE))
res_df <- rbind(res_df, data.frame(
  market="BIST_THYAO", group="no_ext_10", n_feat=10, seed=NA,
  acc=0.496, acc_flip=0.504, naive=0.518, flip_beats=FALSE, stringsAsFactors=FALSE))

write.csv(res_df, file.path(OUTDIR, "mcaware_nasdaq_RESULTS.csv"), row.names=FALSE)

# Özet
summary_df <- res_df %>% group_by(market, group, n_feat) %>%
  summarise(n=n(), mean_acc=mean(acc,na.rm=TRUE), mean_flip=mean(acc_flip,na.rm=TRUE),
            flip_wins=sum(flip_beats,na.rm=TRUE), .groups="drop")
write.csv(summary_df, file.path(OUTDIR, "mcaware_nasdaq_SUMMARY.csv"), row.names=FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.13 — BIST vs NASDAQ KARSILASTIRMA\n")
cat(strrep("=", 80), "\n", sep="")
cat("\nKORELASYON KARSILASTIRMA:\n")
print(corr_all)
cat("\nMODEL KARSILASTIRMA:\n")
print(summary_df)

# Karar
aapl_13_fw <- summary_df$flip_wins[summary_df$market=="NASDAQ_AAPL" & summary_df$group=="full_13"]
thyao_13_fw <- summary_df$flip_wins[summary_df$market=="BIST_THYAO" & summary_df$group=="full_13"]

if (length(aapl_13_fw) > 0 && aapl_13_fw == 0) {
  cat("\n[A] GELISMEKTE OLAN PIYASAYA OZGU:\n")
  cat("    AAPL'de anti-prediktif YOK. THYAO'da VAR.\n")
  cat("    Mekanizma: Turkiye'deki makro rejim degisimi (kur krizi,\n")
  cat("    faiz soklari) BIST'e ozgu korelasyon kirilmasi yaratiyor.\n")
  cat("    ABD piyasasinda bu kadar sert kirilma yok.\n")
} else if (length(aapl_13_fw) > 0 && aapl_13_fw >= 2) {
  cat("\n[B] EVRENSEL PROBLEM:\n")
  cat("    AAPL'de de anti-prediktif! Makro degiskenler HER YERDE\n")
  cat("    DL modellerini yaniltiyor.\n")
} else {
  cat("\n[C] KARISIK:\n")
  cat("    Manuel inceleme gerek.\n")
}

cat(sprintf("\nSure: %.1f dk\n", as.numeric(difftime(t1, t0, units="mins"))))
cat(sprintf("CSV: %s\n", OUTDIR))
cat("\nADIM I.13 TAMAMLANDI.\n")

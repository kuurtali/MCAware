# ===========================================================================
# MC-AWARE — FEATURE ABLATION (ADIM I.11: DIS DEGISKEN TESTI)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   10.31'de THYAO 10 feature ile 0/3 cikti, 13 feature ile 15/15.
#   Hipotez: Dis degiskenler (USDTRY, Oil, TCMB_Rate) anti-prediktif
#   davranisın KAYNAGI.
#   Test: AYNI pipeline, AYNI seed/lambda/CW, SADECE feature seti degisir.
#     Grup A: 13 feature (USDTRY, Oil, TCMB dahil) — v3b ile ayni
#     Grup B: 10 feature (dis degiskenler HARIC)
#   15 kosu her grup (3 lambda x 5 seed)
#
# KARAR:
#   Grup A anti-prediktif + Grup B DEĞİL → DIS DEGISKENLER KAYNAK
#   Her ikisi anti-prediktif → Dis degiskenler degil, baska mekanizma
#   Her ikisi DEĞİL → Pipeline farki (beklenmiyor)
#
# CIKTI: mcaware_feature_ablation_SUMMARY.csv
# Süre: ~45-60 dk (2 x 15 koşu)
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
cat("MC-AWARE — FEATURE ABLATION (ADIM I.11)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Grup A: 13 feat (dis degiskenler DAHIL)\n")
cat("Grup B: 10 feat (dis degiskenler HARIC)\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else { stop("keras3 bidirectional bulunamadi.") }

# --- THYAO veri (v3b ile AYNI) ---
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
cat(sprintf("Final THYAO: %d satir\n", nrow(thyao_final)))

# --- Feature setleri ---
FEAT_GROUPS <- list(
  full_13 = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
              "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate"),
  no_ext_10 = c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
                "SO_K","SO_D","ADX")
)

# --- Loss ---
make_mc_loss <- function(lmc=0) {
  function(yt, yp_) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp <- keras3::op_clip(yp_, eps, one-eps)
    bce <- -(yt*keras3::op_log(yp)+(one-yt)*keras3::op_log(one-yp))
    if (lmc>0) bce+lmc*keras3::op_abs(keras3::op_mean(yp_)-0.5) else bce
  }
}

# --- Grid ---
SEEDS <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS <- c(0.0, 0.05, 0.10)
IN_LEN <- 2L; OUT_LEN <- 3L
prices <- thyao_final$Close

all_results <- list()
t0_all <- Sys.time()

for (grp_name in names(FEAT_GROUPS)) {
  feat_cols <- FEAT_GROUPS[[grp_name]]
  F_DIM <- length(feat_cols)
  feats <- as.matrix(thyao_final[, feat_cols])
  N <- nrow(feats)

  # Pencereleme
  X_list <- list(); y_vec <- c()
  for (t in (IN_LEN+1):(N-OUT_LEN)) {
    X_list[[length(X_list)+1L]] <- feats[(t-IN_LEN+1L):t,, drop=FALSE]
    y_vec <- c(y_vec, as.integer(prices[t+OUT_LEN] > prices[t]))
  }
  X_arr <- array(unlist(X_list), dim=c(length(X_list), IN_LEN, F_DIM))
  y_arr <- y_vec; n_total <- length(y_arr)

  # Split
  i_tr <- floor(n_total*0.70); i_va <- floor(n_total*0.85)
  X_tr <- X_arr[1:i_tr,,, drop=FALSE]; y_tr <- y_arr[1:i_tr]
  X_va <- X_arr[(i_tr+1L):i_va,,, drop=FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
  X_te <- X_arr[(i_va+1L):n_total,,, drop=FALSE]; y_te <- y_arr[(i_va+1L):n_total]

  # Normalize
  mu_a <- apply(X_tr,c(2,3),mean); sd_a <- apply(X_tr,c(2,3),stats::sd)+1e-8
  nf <- function(A) sweep(sweep(A,c(2,3),mu_a,"-"),c(2,3),sd_a,"/")
  X_tr <- nf(X_tr); X_va <- nf(X_va); X_te <- nf(X_te)

  # CW
  n0 <- sum(y_tr==0); n1 <- sum(y_tr==1); nt <- length(y_tr)
  cw <- list("0"=nt/(2*n0), "1"=nt/(2*n1))
  naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))

  cat(sprintf("\n%s\n", strrep("=", 80)))
  cat(sprintf("GRUP: %s (%d feature) | Naive=%.3f\n", grp_name, F_DIM, naive_acc))
  cat(sprintf("%s\n", strrep("=", 80)))

  for (lam in LAMBDAS) {
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
                                  loss=make_mc_loss(lam), metrics=c("accuracy"))
        cb <- keras3::callback_early_stopping(monitor="val_accuracy", patience=5L,
                                               restore_best_weights=TRUE)
        model %>% keras3::fit(X_tr, y_tr, validation_data=list(X_va, y_va),
                              epochs=50L, batch_size=32L, verbose=0L,
                              callbacks=list(cb), class_weight=cw)
        yhat <- as.numeric(predict(model, X_te, verbose=0L))
        pred <- as.integer(yhat > 0.5)
        acc <- mean(pred == y_te); acc_flip <- 1-acc
        tp <- sum(pred==1&y_te==1); tn <- sum(pred==0&y_te==0)
        spec <- if(sum(y_te==0)>0) tn/sum(y_te==0) else NA
        sens <- if(sum(y_te==1)>0) tp/sum(y_te==1) else NA
        is_mc <- isTRUE(spec==0)||isTRUE(sens==0)||is.na(spec)||is.na(sens)

        cat(sprintf("  [%s] lam=%.2f sd=%d: Acc=%.3f flip=%.3f beats=%s MC=%s\n",
                    grp_name, lam, sd, acc, acc_flip, acc_flip>naive_acc, is_mc))

        all_results[[length(all_results)+1]] <- data.frame(
          group=grp_name, n_features=F_DIM, lambda=lam, seed=sd,
          acc=acc, acc_flip=acc_flip, naive_acc=naive_acc,
          flip_beats_naive=acc_flip>naive_acc, is_MC=is_mc,
          yhat_min=min(yhat), yhat_max=max(yhat),
          stringsAsFactors=FALSE)
      }, error=function(e) {
        cat("  HATA:", conditionMessage(e), "\n")
        all_results[[length(all_results)+1]] <<- data.frame(
          group=grp_name, n_features=F_DIM, lambda=lam, seed=sd,
          acc=NA, acc_flip=NA, naive_acc=naive_acc,
          flip_beats_naive=NA, is_MC=NA, yhat_min=NA, yhat_max=NA,
          stringsAsFactors=FALSE)
      })
    }
  }
}

t1_all <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dk\n", as.numeric(difftime(t1_all, t0_all, units="mins"))))

# --- Sonuç ---
results_df <- do.call(rbind, all_results)
write.csv(results_df, file.path(OUTDIR, "mcaware_feature_ablation_RESULTS.csv"), row.names=FALSE)

summary_df <- results_df %>% group_by(group, n_features) %>%
  summarise(n_config=n(), mean_acc=mean(acc,na.rm=TRUE),
            mean_flip=mean(acc_flip,na.rm=TRUE),
            flip_wins=sum(flip_beats_naive,na.rm=TRUE),
            mc_count=sum(is_MC,na.rm=TRUE),
            naive=mean(naive_acc), .groups="drop")
write.csv(summary_df, file.path(OUTDIR, "mcaware_feature_ablation_SUMMARY.csv"), row.names=FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.11 KARAR MATRISI — FEATURE ABLATION\n")
cat(strrep("=", 80), "\n", sep="")
print(summary_df)

fw_full <- summary_df$flip_wins[summary_df$group=="full_13"]
fw_noext <- summary_df$flip_wins[summary_df$group=="no_ext_10"]

cat(sprintf("\nFull 13 feat: flip_wins = %d/15\n", fw_full))
cat(sprintf("No-ext 10 feat: flip_wins = %d/15\n", fw_noext))

if (fw_full >= 12 && fw_noext <= 5) {
  cat("\n[A] DIS DEGISKENLER KAYNAK:\n")
  cat("    Full feature ile anti-prediktif, dis degiskensiz DEGIL.\n")
  cat("    Makroekonomik degiskenler (USDTRY, Oil, TCMB) modeli\n")
  cat("    sistematik olarak YANLIS yone yonlendiriyor.\n")
  cat("    Bu cok onemli bir bulgu: 'hangi feature yaniltiyor'\n")
  cat("    sorusunu yanitliyor.\n")
} else if (fw_full >= 12 && fw_noext >= 12) {
  cat("\n[B] DIS DEGISKENLER DEGIL:\n")
  cat("    Her iki grupta da anti-prediktif. Kaynak baska.\n")
} else if (fw_full <= 5 && fw_noext <= 5) {
  cat("\n[C] HIC ANTI-PREDIKTIF DEGIL:\n")
  cat("    Pipeline farki? Beklenmiyor.\n")
} else {
  cat("\n[D] KARISIK:\n")
  cat(sprintf("    full=%d/15 no_ext=%d/15 — manuel inceleme.\n", fw_full, fw_noext))
}

cat(sprintf("\nCSV: %s\n", OUTDIR))
cat("\nADIM I.11 TAMAMLANDI.\n")

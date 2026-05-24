# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v2.b-fix (FOCAL LOSS + CW=BALANCED KOMBO)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT | Danışman: Övgücan KARADAĞ ERDEMİR
# Tarih: 19.05.2026 (öğle) — v2.b class_weight düzeltmesi
# ---------------------------------------------------------------------------
# NEDEN v2.b-fix?
#   v2.b: alpha=0.25 + class_weight=NULL → Acc=0.45, yhat range=0.07 (BAŞARISIZ)
#
#   ÖNEMLİ DÜZELTME: Bölüm 10.13'teki R2 hipotezi YANLIŞTI!
#   Focal Loss formülü: at = y_true * alpha + (1 - y_true) * (1 - alpha)
#     alpha=0.25 → Up(y=1): at=0.25 (az), Down(y=0): at=0.75 (çok)
#     Yani alpha=0.25 zaten minority'ye (Down) 0.75 ağırlık veriyor — DOĞRU!
#     Alpha değiştirmeye GEREK YOK. Alpha 0.25 olarak KALIYOR.
#
#   GERÇEK SORUN: v2.b'de class_weight=NULL kullanılmıştı.
#   v1.1'de class_weight=balanced → MC=0 sağlanmıştı.
#   v2.b-fix HİPOTEZİ: Focal Loss + CW=balanced KOMBOSU:
#     - CW=balanced model mean(ŷ)≈0.50'ye çeker (MC=0 garanti)
#     - Focal(α=0.25,γ=2.0) hard examples'a odaklanır
#     - KOMBO yhat dağılımını AÇABİLİR (v2.b'deki NULL bunu yapamadı)
#
#   v2.b'den TEK FARK: class_weight = NULL → balanced
#   Alpha, gamma, lambda grid, seed hepsi AYNI.
#
# Çalıştırma: RStudio → Ctrl+Shift+S → ~50-90 dk → 5 CSV üretilir
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ---
WORKDIR <- here::here()
OUTDIR <- here::here()
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
  library(readxl)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v2.b-fix (Focal alpha=0.25 + CW=balanced)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR kullanilacak: ", WORKDIR)
  OUTDIR <- WORKDIR
}

# --- 0a. Bidirectional API tespiti ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
  cat("Bidirectional API: keras3::bidirectional()\n")
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
  cat("Bidirectional API: keras3::layer_bidirectional()\n")
} else {
  stop("keras3 bidirectional bulunamadi.")
}

# --- 0b. Veri dosyasi ---
DATA_FILE <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
if (!file.exists(DATA_FILE)) stop("Veri dosyasi bulunamadi: ", DATA_FILE)

# --- 1. Veri yukleme + ozellik (v1.1 ile birebir ayni) ---
raw <- read_excel(DATA_FILE)
raw <- raw[!is.na(raw$Date), ]
colnames(raw) <- c("Date","Price_ALZ","LogReturn_ALZ",
                   "Price_AZS","LogReturn_AZS",
                   "Price_AMZ","LogReturn_AMZ")
for (c_ in c("Price_AMZ","LogReturn_AMZ")) raw[[c_]] <- as.numeric(raw[[c_]])
amz <- raw %>% filter(!is.na(Price_AMZ)) %>% select(Date, Close = Price_AMZ)

amz$RSI       <- TTR::RSI(amz$Close, n = 14)
ema12         <- TTR::EMA(amz$Close, n = 12)
ema26         <- TTR::EMA(amz$Close, n = 26)
amz$MACD      <- ema12 - ema26
amz$EMA12     <- ema12
amz$EMA26     <- ema26
amz$Momentum  <- amz$Close / dplyr::lag(amz$Close, 14) - 1
amz$Volatility <- zoo::rollapply(c(NA, diff(log(amz$Close))),
                                  width = 14, FUN = stats::sd,
                                  fill = NA, align = "right")
amz <- amz %>% drop_na()

# --- 2. Pencereleme ---
IN_LEN  <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","RSI","MACD","EMA12","EMA26","Momentum","Volatility")
F_DIM <- length(feat_cols)
feats <- as.matrix(amz[, feat_cols]); prices <- amz$Close; N <- nrow(feats)
X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN):(t - 1L), , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec

# --- 3. Split ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr+1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
X_te <- X_arr[(i_va+1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va+1L):n_total]
cat(sprintf("Split: Egitim=%d | Dogrulama=%d | Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))
cat(sprintf("Train Up=%%%.1f | Val Up=%%%.1f | Test Up=%%%.1f\n",
            100*mean(y_tr), 100*mean(y_va), 100*mean(y_te)))

# class_weight hesaplama (v1.1'den geri alindi)
n_up   <- sum(y_tr == 1); n_down <- sum(y_tr == 0); n_train <- length(y_tr)
cw <- list("0" = n_train / (2 * n_down), "1" = n_train / (2 * n_up))
cat(sprintf("class_weight: Down=%.3f Up=%.3f (balanced)\n", cw[["0"]], cw[["1"]]))

# --- 4. Normalization ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 5. Focal Loss + MC_Penalty (KOMBINE LOSS) ---
# Alpha = 0.25 (v2.b ile AYNI — bu zaten Down'a 0.75 ağırlık veriyor, DOĞRU)
# v2.b-fix'in TEK FARKI: class_weight=balanced geri eklendi (Bölüm 8'de)
make_focal_mc_loss <- function(alpha = 0.25, gamma = 2.0, lambda_mc = 0.0) {
  function(y_true, y_pred) {
    eps <- keras3::op_convert_to_tensor(1e-7)
    one <- keras3::op_convert_to_tensor(1.0)
    yp  <- keras3::op_clip(y_pred, eps, one - eps)
    pt  <- y_true * yp + (one - y_true) * (one - yp)
    at  <- y_true * alpha + (one - y_true) * (one - alpha)
    focal <- -at * keras3::op_power(one - pt, gamma) * keras3::op_log(pt)
    if (lambda_mc > 0) {
      mean_pred  <- keras3::op_mean(y_pred)
      mc_penalty <- keras3::op_abs(mean_pred - 0.5)
      focal + lambda_mc * mc_penalty
    } else {
      focal
    }
  }
}

# --- 6. BiLSTM mimarisi (class_weight=balanced GERİ EKLENDİ) ---
build_bilstm <- function(seed, lambda_mc = 0.0,
                          alpha = 0.25, gamma = 2.0) {
  keras3::set_random_seed(seed)
  inner_lstm <- keras3::layer_lstm(units = 64, activation = "tanh",
                                    return_sequences = FALSE)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
  model <- bidir_fn(model, inner_lstm, merge_mode = "concat")
  model <- model %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  model %>% keras3::compile(
    optimizer = keras3::optimizer_adam(),
    loss = make_focal_mc_loss(alpha, gamma, lambda_mc),
    metrics = c("accuracy")
  )
  model
}

# --- 7. Metrik hesabi ---
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
  prec <- if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
  f1   <- if (!is.na(prec) && !is.na(sens) && (prec + sens) > 0)
            2 * prec * sens / (prec + sens) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) ||
           is.na(spec) || is.na(sens)
  list(Acc = acc, Sens = sens, Spec = spec, Prec = prec,
       F1 = f1, BalAcc = bacc, is_MC = is_mc,
       n_pred_Up = sum(pred), n_pred_Down = n - sum(pred))
}

# --- 8. Egit + tahmin (class_weight GERİ EKLENDİ) ---
train_and_predict <- function(seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- build_bilstm(seed, lambda_mc)
    cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                           patience = 5L,
                                           restore_best_weights = TRUE)
    # class_weight = balanced (v2.b'de NULL'du, v2.b-fix'te GERİ ALINDI)
    model %>% keras3::fit(
      X_tr, y_tr,
      validation_data = list(X_va, y_va),
      epochs = 50L, batch_size = 16L, verbose = 0L,
      callbacks = list(cb),
      class_weight = cw  # <--- v2.b'den FARK: balanced class_weight
    )
    yhat_val  <- as.numeric(predict(model, X_va, verbose = 0L))
    yhat_test <- as.numeric(predict(model, X_te, verbose = 0L))
    list(yhat_val = yhat_val, yhat_test = yhat_test, error = NA_character_)
  }, error = function(e) {
    list(yhat_val = rep(NA_real_, length(y_va)),
         yhat_test = rep(NA_real_, length(y_te)),
         error = conditionMessage(e))
  })
}

# --- 9. Grid ---
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim grid: %d lambda x %d seed = %d kosu (Focal alpha=0.25 gamma=2.0)\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
cat("class_weight: BALANCED (v1.1 gibi — v2.b'deki NULL'dan farkli)\n")
cat("TEK DEGISIKLIK (v2.b'den): class_weight=NULL -> balanced\n")
cat(strrep("=", 95), "\n", sep = "")

predictions_list <- list()
threshold_rows   <- list()
optimal_rows     <- list()
yhat_stats_rows  <- list()

t0 <- Sys.time()
for (lam in LAMBDAS) {
  for (sd_seed in SEEDS) {
    cat(sprintf("\nEgitim: lambda=%.2f seed=%d ...\n", lam, sd_seed))
    pred <- train_and_predict(sd_seed, lam)
    if (!is.na(pred$error)) {
      cat(sprintf("  HATA: %s\n", pred$error))
      next
    }

    # yhat dağilim istatistikleri
    yhat_stats_rows[[length(yhat_stats_rows) + 1]] <- data.frame(
      lambda = lam, seed = sd_seed,
      val_min = min(pred$yhat_val), val_max = max(pred$yhat_val),
      val_mean = mean(pred$yhat_val), val_sd = stats::sd(pred$yhat_val),
      test_min = min(pred$yhat_test), test_max = max(pred$yhat_test),
      test_mean = mean(pred$yhat_test), test_sd = stats::sd(pred$yhat_test),
      test_range = max(pred$yhat_test) - min(pred$yhat_test),
      stringsAsFactors = FALSE
    )

    # Predictions sakla
    for (i in seq_along(y_va)) {
      predictions_list[[length(predictions_list) + 1]] <- data.frame(
        lambda = lam, seed = sd_seed, set = "val",
        sample_id = i, yhat = pred$yhat_val[i], y_true = y_va[i],
        stringsAsFactors = FALSE
      )
    }
    for (i in seq_along(y_te)) {
      predictions_list[[length(predictions_list) + 1]] <- data.frame(
        lambda = lam, seed = sd_seed, set = "test",
        sample_id = i, yhat = pred$yhat_test[i], y_true = y_te[i],
        stringsAsFactors = FALSE
      )
    }

    # Threshold grid
    for (thr in THRESHOLDS) {
      m_val  <- compute_metrics(y_va, pred$yhat_val,  thr)
      m_test <- compute_metrics(y_te, pred$yhat_test, thr)
      threshold_rows[[length(threshold_rows) + 1]] <- data.frame(
        lambda = lam, seed = sd_seed, threshold = thr,
        Acc_val = m_val$Acc, BalAcc_val = m_val$BalAcc, F1_val = m_val$F1,
        Sens_val = m_val$Sens, Spec_val = m_val$Spec,
        Acc_test = m_test$Acc, BalAcc_test = m_test$BalAcc, F1_test = m_test$F1,
        Sens_test = m_test$Sens, Spec_test = m_test$Spec,
        is_MC_test = m_test$is_MC,
        stringsAsFactors = FALSE
      )
    }

    # Optimal: BalAcc-max on validation
    val_bacc <- sapply(THRESHOLDS, function(thr) {
      m <- compute_metrics(y_va, pred$yhat_val, thr)
      if (is.na(m$BalAcc)) -Inf else m$BalAcc
    })
    best_idx <- which.max(val_bacc)
    best_thr <- THRESHOLDS[best_idx]
    m_val_best  <- compute_metrics(y_va, pred$yhat_val,  best_thr)
    m_test_best <- compute_metrics(y_te, pred$yhat_test, best_thr)
    m_test_05   <- compute_metrics(y_te, pred$yhat_test, 0.5)

    optimal_rows[[length(optimal_rows) + 1]] <- data.frame(
      lambda = lam, seed = sd_seed,
      best_thr = best_thr,
      val_BalAcc = m_val_best$BalAcc, val_Acc = m_val_best$Acc,
      test_Acc_05 = m_test_05$Acc, test_Spec_05 = m_test_05$Spec,
      test_Sens_05 = m_test_05$Sens, test_BalAcc_05 = m_test_05$BalAcc,
      test_is_MC_05 = m_test_05$is_MC,
      test_Acc_opt = m_test_best$Acc, test_Spec_opt = m_test_best$Spec,
      test_Sens_opt = m_test_best$Sens, test_BalAcc_opt = m_test_best$BalAcc,
      test_is_MC_opt = m_test_best$is_MC,
      stringsAsFactors = FALSE
    )

    cat(sprintf("  yhat dagilim (test): min=%.3f max=%.3f range=%.3f sd=%.3f\n",
                min(pred$yhat_test), max(pred$yhat_test),
                max(pred$yhat_test) - min(pred$yhat_test),
                stats::sd(pred$yhat_test)))
    cat(sprintf("  thr=0.50 -> Acc=%.3f Spec=%.3f Sens=%.3f BalAcc=%.3f MC=%s\n",
                m_test_05$Acc, m_test_05$Spec, m_test_05$Sens, m_test_05$BalAcc,
                if (m_test_05$is_MC) "YES" else "no"))
    cat(sprintf("  thr=%.2f -> Acc=%.3f Spec=%.3f Sens=%.3f BalAcc=%.3f MC=%s\n",
                best_thr, m_test_best$Acc, m_test_best$Spec, m_test_best$Sens,
                m_test_best$BalAcc, if (m_test_best$is_MC) "YES" else "no"))
  }
}
t1 <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dakika\n",
            as.numeric(difftime(t1, t0, units = "mins"))))

# --- 10. Ozet ---
predictions_df <- do.call(rbind, predictions_list)
threshold_df   <- do.call(rbind, threshold_rows)
optimal_df     <- do.call(rbind, optimal_rows)
yhat_stats_df  <- do.call(rbind, yhat_stats_rows)

summary_df <- optimal_df %>%
  group_by(lambda) %>%
  summarise(
    n_seeds = dplyr::n(),
    best_thr_mean = mean(best_thr),
    Acc_05  = mean(test_Acc_05, na.rm = TRUE),
    Spec_05 = mean(test_Spec_05, na.rm = TRUE),
    Sens_05 = mean(test_Sens_05, na.rm = TRUE),
    BalAcc_05 = mean(test_BalAcc_05, na.rm = TRUE),
    MC_05   = sum(test_is_MC_05, na.rm = TRUE),
    Acc_opt  = mean(test_Acc_opt, na.rm = TRUE),
    Spec_opt = mean(test_Spec_opt, na.rm = TRUE),
    Sens_opt = mean(test_Sens_opt, na.rm = TRUE),
    BalAcc_opt = mean(test_BalAcc_opt, na.rm = TRUE),
    MC_opt   = sum(test_is_MC_opt, na.rm = TRUE),
    .groups = "drop"
  )

yhat_summary <- yhat_stats_df %>%
  group_by(lambda) %>%
  summarise(
    test_min_mean = mean(test_min),
    test_max_mean = mean(test_max),
    test_range_mean = mean(test_range),
    test_sd_mean = mean(test_sd),
    .groups = "drop"
  )

cat("\n", strrep("=", 95), "\n", sep = "")
cat("BiLSTM v2.b-fix — OZET (alpha=0.25, CW=balanced)\n")
cat(strrep("=", 95), "\n", sep = "")
cat("\nyhat DAGILIM ozet (lambda basina):\n")
cat("  v1.1 referans: range≈0.16, v2.b referans: range≈0.07, hedef >0.40\n")
print(yhat_summary)
cat("\nMETRIK ozet (thr=0.5 vs thr=BalAcc-opt):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05, MC_05))
cat("\n")
print(summary_df %>% select(lambda, best_thr_mean, Acc_opt, Spec_opt, Sens_opt, BalAcc_opt, MC_opt))

# CSV
out1 <- file.path(OUTDIR, "mcaware_BiLSTM_v2bfix_PREDICTIONS.csv")
out2 <- file.path(OUTDIR, "mcaware_BiLSTM_v2bfix_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR, "mcaware_BiLSTM_v2bfix_OPTIMAL.csv")
out4 <- file.path(OUTDIR, "mcaware_BiLSTM_v2bfix_SUMMARY.csv")
out5 <- file.path(OUTDIR, "mcaware_BiLSTM_v2bfix_YHAT_STATS.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)
write.csv(yhat_stats_df,  out5, row.names = FALSE)

cat("\n5 CSV kaydedildi (00_Tubitak/ altinda):\n")
cat("  ", out1, "\n", "  ", out2, "\n", "  ", out3, "\n", "  ", out4, "\n", "  ", out5, "\n", sep = "")
cat("\n=== v2.b vs v2.b-fix KARŞILAŞTIRMA KRİTERLERİ ===\n")
cat("KRITIK SORU 1: yhat range acildi mi? (test_range_mean > 0.40 -> EVET)\n")
cat("KRITIK SORU 2: thr=opt'ta Acc>0.65 ve Spec>0.30 ve MC=0 mi? (uclu kriterler)\n")
cat("KRITIK SORU 3: v1.1'e gore DAHA MI IYI? (Acc>0.55 + MC=0 korunuyor mu?)\n")
cat("CSV'leri Cowork'e yukle, Bolum 10.14 olarak islenecek.\n")

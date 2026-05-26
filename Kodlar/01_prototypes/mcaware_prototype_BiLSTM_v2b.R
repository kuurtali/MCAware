# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v2.b (FOCAL LOSS + NO BALANCED CLASS_WEIGHT)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT | Danışman: Övgücan KARADAĞ ERDEMİR
# Tarih: 19.05.2026 (gece geç) — v2.a F1-trap sonrası kök sebep müdahalesi
# ---------------------------------------------------------------------------
# NEDEN v2.b?
#   v1.1: MC=0 ama Acc=0.55 (Naive 0.80 altı)
#   v2.a: F1-thr=0.30 seçti -> her şeye Up -> Acc=0.80 AMA Spec=0 (MC geri döndü!)
#   KÖK SORUN (yhat dağılımı analizi, Bölüm 10.12):
#     yhat değerleri 0.43-0.59 aralığında SIKIŞMIŞ (SD=0.02-0.05).
#     class_weight=balanced model yhat'ını 0.5'e itiyor (aşırı dengeleme).
#     Bu dar bant nedeniyle hiçbir threshold gerçek çözüm üretemiyor.
#
# v2.b STRATEJİSİ — yhat dağılımını AÇMAK:
#   (1) class_weight = NULL (KAPALI) — model gerçek class oranını öğrensin
#   (2) Focal Loss (alpha=0.25, gamma=2.0) — minority'yi sample-bazlı, sınıf-toplu değil
#   (3) MC_Penalty hafifletildi: lambda IN {0.0, 0.05, 0.10} (eski 0.5 yok)
#   (4) yhat min/max/SD raporlanıyor — dağılım açıldı mı net görülecek
#   (5) Aynı 5 seed (23, 27, 41, 64, 98)
#   (6) Threshold grid post-hoc (0.30-0.70) + Balanced Accuracy ile optimal seçim
#       (F1 değil — F1 imbalanced datada trivial pred'a saptırır, bkz. v2.a tuzağı)
#
# Hedef: yhat range 0.20-0.80'e açılsın + thr=opt'ta Acc>0.65 + Spec>0.30 + MC=0.
#
# Çalıştırma:
#   1) RStudio'da bu dosyayı aç
#   2) Ctrl+Shift+S (Source)
#   3) ~50-90 dakika bekle (CPU, 12 koşu = 3 lambda x 5 seed eski 20 yerine 15
#      AMA Focal Loss biraz yavaş, beklenen süre benzer)
#   4) 00_Tubitak/ altındaki 4 CSV'yi Cowork'e yükle
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
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(keras3)
  library(tensorflow)
  library(readxl)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v2.b (Focal Loss + No CW)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
 # ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v2.b (FOCAL LOSS + NO BALANCED CLASS_WEIGHT)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT | Danışman: Övgücan KARADAĞ ERDEMİR
# Tarih: 19.05.2026 (gece geç) — v2.a F1-trap sonrası kök sebep müdahalesi
# ---------------------------------------------------------------------------
# NEDEN v2.b?
#   v1.1: MC=0 ama Acc=0.55 (Naive 0.80 altı)
#   v2.a: F1-thr=0.30 seçti -> her şeye Up -> Acc=0.80 AMA Spec=0 (MC geri döndü!)
#   KÖK SORUN (yhat dağılımı analizi, Bölüm 10.12):
#     yhat değerleri 0.43-0.59 aralığında SIKIŞMIŞ (SD=0.02-0.05).
#     class_weight=balanced model yhat'ını 0.5'e itiyor (aşırı dengeleme).
#     Bu dar bant nedeniyle hiçbir threshold gerçek çözüm üretemiyor.
#
# v2.b STRATEJİSİ — yhat dağılımını AÇMAK:
#   (1) class_weight = NULL (KAPALI) — model gerçek class oranını öğrensin
#   (2) Focal Loss (alpha=0.25, gamma=2.0) — minority'yi sample-bazlı, sınıf-toplu değil
#   (3) MC_Penalty hafifletildi: lambda IN {0.0, 0.05, 0.10} (eski 0.5 yok)
#   (4) yhat min/max/SD raporlanıyor — dağılım açıldı mı net görülecek
#   (5) Aynı 5 seed (23, 27, 41, 64, 98)
#   (6) Threshold grid post-hoc (0.30-0.70) + Balanced Accuracy ile optimal seçim
#       (F1 değil — F1 imbalanced datada trivial pred'a saptırır, bkz. v2.a tuzağı)
#
# Hedef: yhat range 0.20-0.80'e açılsın + thr=opt'ta Acc>0.65 + Spec>0.30 + MC=0.
#
# Çalıştırma:
#   1) RStudio'da bu dosyayı aç
#   2) Ctrl+Shift+S (Source)
#   3) ~50-90 dakika bekle (CPU, 12 koşu = 3 lambda x 5 seed eski 20 yerine 15
#      AMA Focal Loss biraz yavaş, beklenen süre benzer)
#   4) 00_Tubitak/ altındaki 4 CSV'yi Cowork'e yükle
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
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(keras3)
  library(tensorflow)
  library(readxl)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v2.b (Focal Loss + No CW)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR kullanilacak: ", WORKDIR)
# [B18]   OUTDIR <- WORKDIR
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

# --- 4. Normalization ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 5. Focal Loss + MC_Penalty (KOMBINE LOSS) ---
# Focal Loss formul: -alpha * (1 - p_t)^gamma * log(p_t)
# p_t = y_true * y_pred + (1 - y_true) * (1 - y_pred)
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

# --- 6. BiLSTM mimarisi (v1.1 ile ayni, AMA class_weight YOK + Focal Loss) ---
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

# --- 8. Egit + tahmin ---
train_and_predict <- function(seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- build_bilstm(seed, lambda_mc)
    cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                           patience = 5L,
                                           restore_best_weights = TRUE)
    # class_weight YOK — bilinçli olarak kapali
    model %>% keras3::fit(
      X_tr, y_tr,
      validation_data = list(X_va, y_va),
      epochs = 50L, batch_size = 16L, verbose = 0L,
      callbacks = list(cb)
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
LAMBDAS    <- c(0.0, 0.05, 0.10)   # daha hafif
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim grid: %d lambda x %d seed = %d kosu (Focal alpha=0.25 gamma=2.0)\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
cat("class_weight: NULL (KAPALI — v1.1 ve v2.a'dan farkli)\n")
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

    # yhat dağilim istatistikleri (KRITIK: v2.b'nin amaci range acmak)
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

    # Optimal: BalAcc-max on validation (F1 DEGIL — v2.a tuzagindan ders alindi)
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
cat("BiLSTM v2.b — OZET\n")
cat(strrep("=", 95), "\n", sep = "")
cat("\nyhat DAĞILIM özet (lambda başına, v1.1'de range≈0.15, hedef >0.40):\n")
print(yhat_summary)
cat("\nMETRIK özet (thr=0.5 vs thr=BalAcc-opt):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05, MC_05))
cat("\n")
print(summary_df %>% select(lambda, best_thr_mean, Acc_opt, Spec_opt, Sens_opt, BalAcc_opt, MC_opt))

# CSV
out1 <- file.path(OUTDIR_PRED, "mcaware_BiLSTM_v2b_PREDICTIONS.csv")
out2 <- file.path(OUTDIR_THR, "mcaware_BiLSTM_v2b_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR_SUM, "mcaware_BiLSTM_v2b_OPTIMAL.csv")
out4 <- file.path(OUTDIR_SUM, "mcaware_BiLSTM_v2b_SUMMARY.csv")
out5 <- file.path(OUTDIR_DIAG, "mcaware_BiLSTM_v2b_YHAT_STATS.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)
write.csv(yhat_stats_df,  out5, row.names = FALSE)

cat("\n5 CSV kaydedildi (00_Tubitak/ altinda):\n")
cat("  ", out1, "\n", "  ", out2, "\n", "  ", out3, "\n", "  ", out4, "\n", "  ", out5, "\n", sep = "")
cat("\nKRITIK SORU 1: yhat range acildi mi? (test_range_mean > 0.40 -> EVET)\n")
cat("KRITIK SORU 2: thr=opt'ta Acc>0.65 ve Spec>0.30 ve MC=0 mi? (uclu kriterler)\n")
cat("CSV'leri Cowork'e yukle, Bolum 10.13 olarak islenecek.\n")
.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' 
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR kullanilacak: ", WORKDIR)
# [B18]   OUTDIR <- WORKDIR
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

# --- 4. Normalization ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 5. Focal Loss + MC_Penalty (KOMBINE LOSS) ---
# Focal Loss formul: -alpha * (1 - p_t)^gamma * log(p_t)
# p_t = y_true * y_pred + (1 - y_true) * (1 - y_pred)
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

# --- 6. BiLSTM mimarisi (v1.1 ile ayni, AMA class_weight YOK + Focal Loss) ---
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

# --- 8. Egit + tahmin ---
train_and_predict <- function(seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- build_bilstm(seed, lambda_mc)
    cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                           patience = 5L,
                                           restore_best_weights = TRUE)
    # class_weight YOK — bilinçli olarak kapali
    model %>% keras3::fit(
      X_tr, y_tr,
      validation_data = list(X_va, y_va),
      epochs = 50L, batch_size = 16L, verbose = 0L,
      callbacks = list(cb)
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
LAMBDAS    <- c(0.0, 0.05, 0.10)   # daha hafif
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim grid: %d lambda x %d seed = %d kosu (Focal alpha=0.25 gamma=2.0)\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
cat("class_weight: NULL (KAPALI — v1.1 ve v2.a'dan farkli)\n")
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

    # yhat dağilim istatistikleri (KRITIK: v2.b'nin amaci range acmak)
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

    # Optimal: BalAcc-max on validation (F1 DEGIL — v2.a tuzagindan ders alindi)
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
cat("BiLSTM v2.b — OZET\n")
cat(strrep("=", 95), "\n", sep = "")
cat("\nyhat DAĞILIM özet (lambda başına, v1.1'de range≈0.15, hedef >0.40):\n")
print(yhat_summary)
cat("\nMETRIK özet (thr=0.5 vs thr=BalAcc-opt):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05, MC_05))
cat("\n")
print(summary_df %>% select(lambda, best_thr_mean, Acc_opt, Spec_opt, Sens_opt, BalAcc_opt, MC_opt))

# CSV
out1 <- file.path(OUTDIR_PRED, "mcaware_BiLSTM_v2b_PREDICTIONS.csv")
out2 <- file.path(OUTDIR_THR, "mcaware_BiLSTM_v2b_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR_SUM, "mcaware_BiLSTM_v2b_OPTIMAL.csv")
out4 <- file.path(OUTDIR_SUM, "mcaware_BiLSTM_v2b_SUMMARY.csv")
out5 <- file.path(OUTDIR_DIAG, "mcaware_BiLSTM_v2b_YHAT_STATS.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)
write.csv(yhat_stats_df,  out5, row.names = FALSE)

cat("\n5 CSV kaydedildi (00_Tubitak/ altinda):\n")
cat("  ", out1, "\n", "  ", out2, "\n", "  ", out3, "\n", "  ", out4, "\n", "  ", out5, "\n", sep = "")
cat("\nKRITIK SORU 1: yhat range acildi mi? (test_range_mean > 0.40 -> EVET)\n")
cat("KRITIK SORU 2: thr=opt'ta Acc>0.65 ve Spec>0.30 ve MC=0 mi? (uclu kriterler)\n")
cat("CSV'leri Cowork'e yukle, Bolum 10.13 olarak islenecek.\n")

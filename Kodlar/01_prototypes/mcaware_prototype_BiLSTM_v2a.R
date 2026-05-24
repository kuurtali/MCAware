# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v2.a (THRESHOLD OPTIMIZATION)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT | Danışman: Övgücan KARADAĞ ERDEMİR
# Tarih: 19.05.2026 (gece) — v1.1 sonrası "MC çözüldü ama Acc çöktü" düzeltmesi
# ---------------------------------------------------------------------------
# AMAÇ:
#   v1.1'de MC_count=0 oldu AMA Acc=0.54-0.55 (Naive %80'in altında). Bunun
#   temel sebebi: BiLSTM + class_weight=balanced kombinasyonu modelin tahminini
#   mean(yhat) ≈ 0.50'ye çekiyor, sabit 0.5 threshold bu dengeyi sürdürüyor.
#   v2.a: Aynı modelleri eğit AMA yhat'ı kaydet, sonra VALIDATION setinde
#         F1-optimal threshold ara. Test'te bu threshold ile yeniden değerlendir.
#
# DEĞİŞİKLİK (v2.a vs v1.1):
#   [+] Tüm yhat değerleri saklanır (val + test)
#   [+] Threshold grid: c(0.30, 0.35, 0.40, ..., 0.70)
#   [+] Validation'da F1-optimal threshold seçilir
#   [+] Test'te (a) sabit 0.5 ve (b) optimal threshold ile değerlendirme
#   [+] Çıktı dosyaları doğrudan 00_Tubitak/ klasörüne kaydedilir
#
# Karşılaştırma (v1.1 vs v2.a beklentisi):
#   v1.1: thr=0.5 → Acc=0.54, Spec=0.43, Sens=0.58
#   v2.a hedef: thr=opt → Acc≥0.65, Spec≥0.40, Sens≥0.70 (Naive %80 hedefe yakın)
#
# Çalıştırma:
#   1) RStudio'da bu dosyayı aç
#   2) Ctrl+Shift+S (Source)
#   3) ~50-90 dakika bekle (CPU, eğitim v1.1 ile aynı — threshold ekstra hızlı)
#   4) 00_Tubitak/ altındaki 4 CSV'yi Cowork'e geri yükle
#
# Çıktı dosyaları (otomatik 00_Tubitak/ altına kaydedilir):
#   - mcaware_BiLSTM_v2a_PREDICTIONS.csv       (uzun format, tüm yhat'lar)
#   - mcaware_BiLSTM_v2a_THRESHOLD_GRID.csv    (her threshold için val+test metrikleri)
#   - mcaware_BiLSTM_v2a_OPTIMAL.csv           (her konfig için optimal threshold)
#   - mcaware_BiLSTM_v2a_SUMMARY.csv           (lambda x threshold tipi ozet)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ayarlari ---
WORKDIR <- here::here()
OUTDIR <- here::here()   # CSV'ler buraya
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
cat("MC-AWARE PROTOTYPE — BiLSTM v2.a (Threshold Optimization)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("R surumu:", R.version.string, "\n")
cat("keras3 surumu:", as.character(packageVersion("keras3")), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("========================================================================\n\n")

# Cikti klasoru var mi?
if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru bulunamadi: ", OUTDIR, "\n",
          "WORKDIR altina kaydedilecek: ", WORKDIR)
  OUTDIR <- WORKDIR
}

# --- 0a. Bidirectional API tespiti (keras3 surum uyumlulugu) ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
  cat("Bidirectional API: keras3::bidirectional()\n")
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
  cat("Bidirectional API: keras3::layer_bidirectional()\n")
} else {
  stop("HATA: keras3'te bidirectional bulunamadi. keras3::install_keras() calistir.")
}

# --- 0b. Veri dosyasi varlik kontrolu ---
DATA_FILE <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
if (!file.exists(DATA_FILE)) {
  stop("HATA: Veri dosyasi bulunamadi: ", DATA_FILE)
}

# --- 1. Veri yukleme ---
raw <- read_excel(DATA_FILE)
raw <- raw[!is.na(raw$Date), ]
colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                    "Price_AZS", "LogReturn_AZS",
                    "Price_AMZ", "LogReturn_AMZ")
for (c_ in c("Price_AMZ", "LogReturn_AMZ")) raw[[c_]] <- as.numeric(raw[[c_]])
amz <- raw %>% filter(!is.na(Price_AMZ)) %>% select(Date, Close = Price_AMZ)

# --- 2. Ozellik muhendisligi (full set, v1.1 ile ayni) ---
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
cat(sprintf("AMZ veri (warmup sonrasi): %d hafta\n", nrow(amz)))

# --- 3. Pencereleme (In=2, Out=3) ---
IN_LEN  <- 2L
OUT_LEN <- 3L
feat_cols <- c("Close", "RSI", "MACD", "EMA12", "EMA26", "Momentum", "Volatility")
F_DIM <- length(feat_cols)

feats <- as.matrix(amz[, feat_cols])
prices <- amz$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN):(t - 1L), , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec

# --- 4. Split (70/15/15 kronolojik, v1.1 ile ayni) ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70)
i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr + 1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr + 1L):i_va]
X_te <- X_arr[(i_va + 1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va + 1L):n_total]

cat(sprintf("Split: Egitim=%d | Dogrulama=%d | Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))
cat(sprintf("Val Up=%%%.1f (Up=%d, Down=%d)\n",
            100 * mean(y_va), sum(y_va), length(y_va) - sum(y_va)))
cat(sprintf("Test Up=%%%.1f (Up=%d, Down=%d)\n",
            100 * mean(y_te), sum(y_te), length(y_te) - sum(y_te)))

# --- 5. Train-only normalization ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 6. MC-Aware Loss (v1.1 ile ayni) ---
make_mc_aware_loss <- function(lambda) {
  function(y_true, y_pred) {
    bce <- keras3::loss_binary_crossentropy(y_true, y_pred)
    mean_pred <- keras3::op_mean(y_pred)
    mc_penalty <- keras3::op_abs(mean_pred - 0.5)
    bce + lambda * mc_penalty
  }
}

# --- 7. BiLSTM model fabrikasi (v1.1 ile ayni) ---
build_bilstm <- function(seed, lambda_mc = 0.0) {
  keras3::set_random_seed(seed)
  inner_lstm <- keras3::layer_lstm(units = 64, activation = "tanh",
                                    return_sequences = FALSE)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
  model <- bidir_fn(model, inner_lstm, merge_mode = "concat")
  model <- model %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")
  n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1)
  cw <- list("0" = length(y_tr) / (2 * max(n0, 1)),
             "1" = length(y_tr) / (2 * max(n1, 1)))
  if (lambda_mc == 0.0) {
    model %>% keras3::compile(
      optimizer = keras3::optimizer_adam(),
      loss = "binary_crossentropy",
      metrics = c("accuracy")
    )
  } else {
    model %>% keras3::compile(
      optimizer = keras3::optimizer_adam(),
      loss = make_mc_aware_loss(lambda_mc),
      metrics = c("accuracy")
    )
  }
  list(model = model, class_weight = cw)
}

# --- 8. Metrik hesaplama yardimcisi ---
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
       F1 = f1, BalAcc = bacc, n_pred_Up = sum(pred),
       n_pred_Down = n - sum(pred), is_MC = is_mc)
}

# --- 9. Egit + yhat sakla (her config icin) ---
train_and_predict <- function(seed, lambda_mc) {
  keras3::clear_session()
  result <- tryCatch({
    bundle <- build_bilstm(seed, lambda_mc)
    cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                           patience = 5L,
                                           restore_best_weights = TRUE)
    bundle$model %>% keras3::fit(
      X_tr, y_tr,
      validation_data = list(X_va, y_va),
      epochs = 50L, batch_size = 16L, verbose = 0L,
      callbacks = list(cb), class_weight = bundle$class_weight
    )
    yhat_val  <- as.numeric(predict(bundle$model, X_va, verbose = 0L))
    yhat_test <- as.numeric(predict(bundle$model, X_te, verbose = 0L))
    list(yhat_val = yhat_val, yhat_test = yhat_test, error = NA_character_)
  }, error = function(e) {
    list(yhat_val = rep(NA_real_, length(y_va)),
         yhat_test = rep(NA_real_, length(y_te)),
         error = conditionMessage(e))
  })
  result
}

# --- 10. Grid: lambda x seed (v1.1 ile ayni) ---
SEEDS   <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS <- c(0.0, 0.1, 0.3, 0.5)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim grid: %d lambda x %d seed = %d kosu\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
cat(sprintf("Threshold grid: %d nokta (%.2f -> %.2f, step 0.05)\n",
            length(THRESHOLDS), min(THRESHOLDS), max(THRESHOLDS)))
cat(strrep("=", 95), "\n", sep = "")

predictions_list <- list()
threshold_rows   <- list()
optimal_rows     <- list()

t0 <- Sys.time()
for (lam in LAMBDAS) {
  for (sd_seed in SEEDS) {
    cat(sprintf("\nEgitim: lambda=%.1f seed=%d ...\n", lam, sd_seed))
    pred <- train_and_predict(sd_seed, lam)
    if (!is.na(pred$error)) {
      cat(sprintf("  HATA: %s\n", pred$error))
      next
    }

    # Predictions sakla (uzun format)
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

    # Threshold grid: val + test metrikleri
    for (thr in THRESHOLDS) {
      m_val  <- compute_metrics(y_va, pred$yhat_val,  thr)
      m_test <- compute_metrics(y_te, pred$yhat_test, thr)
      threshold_rows[[length(threshold_rows) + 1]] <- data.frame(
        lambda = lam, seed = sd_seed, threshold = thr,
        Acc_val = m_val$Acc, F1_val = m_val$F1, BalAcc_val = m_val$BalAcc,
        Sens_val = m_val$Sens, Spec_val = m_val$Spec,
        Acc_test = m_test$Acc, F1_test = m_test$F1, BalAcc_test = m_test$BalAcc,
        Sens_test = m_test$Sens, Spec_test = m_test$Spec,
        is_MC_test = m_test$is_MC,
        stringsAsFactors = FALSE
      )
    }

    # Optimal threshold: F1-max on validation
    val_metrics <- sapply(THRESHOLDS, function(thr) {
      m <- compute_metrics(y_va, pred$yhat_val, thr)
      if (is.na(m$F1)) -Inf else m$F1
    })
    best_idx <- which.max(val_metrics)
    best_thr <- THRESHOLDS[best_idx]
    m_val_best  <- compute_metrics(y_va, pred$yhat_val,  best_thr)
    m_test_best <- compute_metrics(y_te, pred$yhat_test, best_thr)
    m_test_05   <- compute_metrics(y_te, pred$yhat_test, 0.5)

    optimal_rows[[length(optimal_rows) + 1]] <- data.frame(
      lambda = lam, seed = sd_seed,
      best_thr = best_thr,
      val_F1 = m_val_best$F1, val_Acc = m_val_best$Acc,
      test_F1_05 = m_test_05$F1, test_Acc_05 = m_test_05$Acc,
      test_Spec_05 = m_test_05$Spec, test_Sens_05 = m_test_05$Sens,
      test_is_MC_05 = m_test_05$is_MC,
      test_F1_opt = m_test_best$F1, test_Acc_opt = m_test_best$Acc,
      test_Spec_opt = m_test_best$Spec, test_Sens_opt = m_test_best$Sens,
      test_is_MC_opt = m_test_best$is_MC,
      stringsAsFactors = FALSE
    )

    cat(sprintf("  thr=0.50 -> Acc=%.3f Spec=%.3f Sens=%.3f F1=%.3f MC=%s\n",
                m_test_05$Acc, m_test_05$Spec, m_test_05$Sens, m_test_05$F1,
                if (m_test_05$is_MC) "YES" else "no"))
    cat(sprintf("  thr=%.2f -> Acc=%.3f Spec=%.3f Sens=%.3f F1=%.3f MC=%s  (val F1=%.3f)\n",
                best_thr, m_test_best$Acc, m_test_best$Spec, m_test_best$Sens,
                m_test_best$F1, if (m_test_best$is_MC) "YES" else "no",
                m_val_best$F1))
  }
}
t1 <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dakika\n",
            as.numeric(difftime(t1, t0, units = "mins"))))

# --- 11. CSV ciktilari ---
predictions_df <- do.call(rbind, predictions_list)
threshold_df   <- do.call(rbind, threshold_rows)
optimal_df     <- do.call(rbind, optimal_rows)

# Summary: thr=0.5 (v1.1 ile karsilastirma) vs thr=opt
summary_df <- optimal_df %>%
  group_by(lambda) %>%
  summarise(
    n_seeds = dplyr::n(),
    best_thr_mean = mean(best_thr),
    # Sabit 0.5 ile (v1.1 reprodüksiyonu)
    Acc_05  = mean(test_Acc_05, na.rm = TRUE),
    Spec_05 = mean(test_Spec_05, na.rm = TRUE),
    Sens_05 = mean(test_Sens_05, na.rm = TRUE),
    F1_05   = mean(test_F1_05, na.rm = TRUE),
    MC_05   = sum(test_is_MC_05, na.rm = TRUE),
    # F1-optimal threshold ile
    Acc_opt  = mean(test_Acc_opt, na.rm = TRUE),
    Spec_opt = mean(test_Spec_opt, na.rm = TRUE),
    Sens_opt = mean(test_Sens_opt, na.rm = TRUE),
    F1_opt   = mean(test_F1_opt, na.rm = TRUE),
    MC_opt   = sum(test_is_MC_opt, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n", strrep("=", 95), "\n", sep = "")
cat("OZET — lambda basina 5-seed ortalamasi (BiLSTM v2.a)\n")
cat(strrep("=", 95), "\n", sep = "")
cat("Sabit 0.5 threshold (v1.1 reprodüksiyonu):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, F1_05, MC_05))
cat("\nF1-optimal threshold (v2.a yeni):\n")
print(summary_df %>% select(lambda, best_thr_mean, Acc_opt, Spec_opt, Sens_opt, F1_opt, MC_opt))

# CSV yaz
out1 <- file.path(OUTDIR, "mcaware_BiLSTM_v2a_PREDICTIONS.csv")
out2 <- file.path(OUTDIR, "mcaware_BiLSTM_v2a_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR, "mcaware_BiLSTM_v2a_OPTIMAL.csv")
out4 <- file.path(OUTDIR, "mcaware_BiLSTM_v2a_SUMMARY.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)

cat("\nCSV'ler kaydedildi:\n")
cat("  ", out1, "\n")
cat("  ", out2, "\n")
cat("  ", out3, "\n")
cat("  ", out4, "\n")
cat("\nBu 4 CSV'yi Cowork'e yukle, Bolum 10.12 olarak islenecek.\n")
cat("KRITIK SORU: Acc_opt > Naive (0.80) mu? Eger evet, v2.a yeterli olabilir.\n")
cat("             Eger hayir, v2.b (Focal Loss + class_weight=sqrt) sıraya girer.\n")

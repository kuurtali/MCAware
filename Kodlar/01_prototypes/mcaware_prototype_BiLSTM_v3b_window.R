# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v3b WINDOW (ADIM I.4: LAG TUZAĞI TESTİ)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 19.05.2026 — v3 THYAO'nun PENCERE-DÜZELTİLMİŞ kopyası
# ---------------------------------------------------------------------------
# NE FARKLI?
#   v3 (orijinal): X = feats[(t - IN_LEN):(t - 1L)]  → günler {t-2, t-1}
#                  y = price[t + OUT_LEN] > price[t]  → anchor = t
#                  → X son günü (t-1) ile label anchor (t) ARASI 1 GÜN BOŞLUK
#                  → Model day-t'yi GÖRMÜYOR ama label day-t'ye bağımlı
#
#   v3b (bu):      X = feats[(t - IN_LEN + 1L):t]  → günler {t-1, t}
#                  y = price[t + OUT_LEN] > price[t]  → anchor = t (AYNI)
#                  → X son günü = label anchor = t
#                  → BOŞLUK YOK, hizalı setup
#
# AMACI:
#   v3'te THYAO test setinde gözlenen 15/15 anti-prediktif davranış
#   (acc_orig=0.42, acc_flip=0.58, p≈3e-5) ÜÇ ŞEYDEN BİRİ olabilir:
#     (a) Off-by-one etiket bug — ADIM I.3'te ELENDI (formül aynı).
#     (b) CW=balanced contrarian rejimi
#     (c) BIST günlük reversal sinyali
#     (d) X-y LAG TUZAĞI: input son günü ile label anchor arası 1 gün
#         boşluk + day-t'nin kendi hareketi yön sinyalini ters yansıtıyor
#
# v3b SONUÇLARI — KARAR MATRİSİ:
#   A) acc_orig ≥ 0.50, flip artık galip değil (15/15 → ≤7/15)
#      → Hipotez (d) DOĞRULANDI. "Lag tuzağı keşfi" pozitif ama Yorum 3
#        (contrarian) ZAYIFLAR. Asıl bulgu: doğru pencerelemeyle model
#        anlamlı tahmin yapabiliyor.
#   B) acc_orig HÂLÂ ≈0.42, 15/15 flip yine galip
#      → Hipotez (d) ELENDI, (b)+(c) kalıyor. Yorum 3 GÜÇLÜ — gerçek
#        anomali (BIST reversal).
#   C) acc_orig ≈ 0.50, fark yok (random)
#      → Sinyal zayıf, Yorum 1' (rafine reframe) tek geçerli yol.
#
# ÇIKTI: v3 ile YAN-YANA KARŞILAŞTIRMA için aynı CSV formatı.
#        5 CSV: PREDICTIONS, THRESHOLD_GRID, OPTIMAL, SUMMARY, YHAT_STATS.
#
# Çalıştırma: RStudio → Ctrl+Shift+S → ~30-45 dk → 5 CSV
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
  library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v3b WINDOW (ADIM I.4 LAG TUZAGI TESTI)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("v3'ten TEK FARK: X = feats[(t-IN_LEN+1):t] (anchor gunu DAHIL)\n")
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

# --- 1. THYAO veri çekme (Yahoo Finance) — v3 ile AYNI ---
cat("THYAO verisi Yahoo Finance'den cekiliyor...\n")
getSymbols("THYAO.IS", from = "2018-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)

thyao_xts <- THYAO.IS
thyao_df <- data.frame(
  Date   = as.character(index(thyao_xts)),
  Open   = as.numeric(Op(thyao_xts)),
  High   = as.numeric(Hi(thyao_xts)),
  Low    = as.numeric(Lo(thyao_xts)),
  Close  = as.numeric(Cl(thyao_xts)),
  Volume = as.numeric(Vo(thyao_xts))
)
thyao_df <- thyao_df[thyao_df$Volume > 0, ]
thyao_df <- thyao_df[complete.cases(thyao_df[, c("Open","High","Low","Close")]), ]
cat(sprintf("Ham THYAO: %d satir\n", nrow(thyao_df)))

# --- 2. Teknik göstergeler — v3 ile AYNI ---
thyao_df$RSI   <- TTR::RSI(thyao_df$Close, n = 14)
macd_vals      <- TTR::MACD(thyao_df$Close)
thyao_df$MACD  <- macd_vals[, "macd"]
thyao_df$EMA12 <- TTR::EMA(thyao_df$Close, n = 12)
thyao_df$EMA26 <- TTR::EMA(thyao_df$Close, n = 26)
stoch_vals     <- TTR::stoch(thyao_df[, c("High", "Low", "Close")])
thyao_df$SO_K  <- stoch_vals[, "fastK"]
thyao_df$SO_D  <- stoch_vals[, "fastD"]
adx_vals       <- TTR::ADX(thyao_df[, c("High", "Low", "Close")])
thyao_df$ADX   <- adx_vals[, "ADX"]

# Dış değişkenler — v3 ile AYNI
cat("Dis degiskenler cekiliyor (USDTRY, Oil, TCMB)...\n")
tryCatch({
  getSymbols("USDTRY=X", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  usdtry_df <- data.frame(
    Date   = as.character(index(`USDTRY=X`)),
    USDTRY = as.numeric(Cl(`USDTRY=X`))
  )
}, error = function(e) {
  cat("USDTRY cekilemedi, atlaniyor\n")
  usdtry_df <<- data.frame(Date = character(0), USDTRY = numeric(0))
})

tryCatch({
  getSymbols("CL=F", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  oil_df <- data.frame(
    Date = as.character(index(`CL=F`)),
    Oil  = as.numeric(Cl(`CL=F`))
  )
}, error = function(e) {
  cat("Oil cekilemedi, atlaniyor\n")
  oil_df <<- data.frame(Date = character(0), Oil = numeric(0))
})

tryCatch({
  getSymbols("INTDSRTRM193N", src = "FRED", from = "2018-01-01",
             to = "2026-03-31", auto.assign = TRUE, warnings = FALSE)
  tcmb_df <- data.frame(
    Date      = as.Date(index(INTDSRTRM193N)),
    TCMB_Rate = as.numeric(INTDSRTRM193N)
  )
  tcmb_daily <- data.frame(Date = as.Date(thyao_df$Date)) %>%
    mutate(YearMonth = format(Date, "%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth = format(Date, "%Y-%m")),
              by = "YearMonth") %>%
    select(Date = Date.x, TCMB_Rate)
}, error = function(e) {
  cat("TCMB cekilemedi, atlaniyor\n")
  tcmb_daily <<- data.frame(Date = as.Date(thyao_df$Date),
                             TCMB_Rate = NA_real_)
})

# Birleştir — v3 ile AYNI
thyao_final <- thyao_df %>%
  left_join(usdtry_df, by = "Date") %>%
  left_join(oil_df, by = "Date") %>%
  left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")

thyao_final$USDTRY    <- zoo::na.locf(thyao_final$USDTRY, na.rm = FALSE)
thyao_final$Oil       <- zoo::na.locf(thyao_final$Oil, na.rm = FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm = FALSE)

# İlk 27 satır gösterge ısınması — v3 ile AYNI
thyao_final <- thyao_final[28:nrow(thyao_final), ]
thyao_final <- thyao_final %>% drop_na()
cat(sprintf("Final THYAO: %d satir (gunluk, 2018-2026)\n", nrow(thyao_final)))

# --- 3. Pencereleme — KRİTİK DEĞİŞİKLİK BURADA ---
IN_LEN  <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

cat("\n*** PENCERE DEGISIKLIGI (v3 vs v3b) ***\n")
cat("  v3 ORIJINAL: X = feats[(t - IN_LEN):(t - 1L)]      -> gunler {t-2, t-1}\n")
cat("  v3b YENI:    X = feats[(t - IN_LEN + 1L):t]        -> gunler {t-1, t}\n")
cat("  Label AYNI:  y = price[t + OUT_LEN] > price[t]\n")
cat("  Loop AYNI:   t in (IN_LEN+1) : (N - OUT_LEN)\n")
cat("  Yani v3 ile v3b TEK FARKI X penceresi.\n\n")

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  # *** TEK FARK: pencere 1 gün ileri kaydı, anchor günü DAHIL ***
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
cat(sprintf("Pencere sayisi: %d (In=%d, Out=%d, %d feature)\n",
            length(y_arr), IN_LEN, OUT_LEN, F_DIM))

# --- 4. Split — v3 ile AYNI ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr+1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
X_te <- X_arr[(i_va+1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va+1L):n_total]
cat(sprintf("Split: Egitim=%d | Dogrulama=%d | Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))
cat(sprintf("Train Up=%%%.1f | Val Up=%%%.1f | Test Up=%%%.1f\n",
            100*mean(y_tr), 100*mean(y_va), 100*mean(y_te)))

# class_weight (balanced) — v3 ile AYNI
n_up <- sum(y_tr == 1); n_down <- sum(y_tr == 0); n_train <- length(y_tr)
cw <- list("0" = n_train / (2 * n_down), "1" = n_train / (2 * n_up))
cat(sprintf("class_weight: Down=%.3f Up=%.3f (balanced)\n", cw[["0"]], cw[["1"]]))

# Naive baseline — v3 ile AYNI
naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
cat(sprintf("NAIVE BASELINE (hep majority): Acc = %.4f\n", naive_acc))

# --- 5. Normalization — v3 ile AYNI ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 6. Loss (BCE + MC_Penalty, NO Focal) — v3 ile AYNI ---
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

# --- 7. BiLSTM mimarisi — v3 ile AYNI ---
build_bilstm <- function(seed, lambda_mc = 0.0) {
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
    loss = make_mc_loss(lambda_mc),
    metrics = c("accuracy")
  )
  model
}

# --- 8. Metrik hesabi — v3 ile AYNI ---
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
  f1   <- if (!is.na(prec_) && !is.na(sens) && (prec_ + sens) > 0)
            2 * prec_ * sens / (prec_ + sens) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) ||
           is.na(spec) || is.na(sens)
  # FLIP-Acc EK METRIK (I.3'ten ilham): tahminleri ters cevirip Acc
  acc_flip <- 1 - acc
  list(Acc = acc, Sens = sens, Spec = spec, Prec = prec_,
       F1 = f1, BalAcc = bacc, is_MC = is_mc, Acc_flip = acc_flip,
       n_pred_Up = sum(pred), n_pred_Down = n - sum(pred))
}

# --- 9. Egit + tahmin — v3 ile AYNI ---
train_and_predict <- function(seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- build_bilstm(seed, lambda_mc)
    cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                           patience = 5L,
                                           restore_best_weights = TRUE)
    model %>% keras3::fit(
      X_tr, y_tr,
      validation_data = list(X_va, y_va),
      epochs = 50L, batch_size = 32L, verbose = 0L,
      callbacks = list(cb),
      class_weight = cw
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

# --- 10. Grid — v3 ile AYNI (karsilastirilabilirlik icin) ---
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim: %d lambda x %d seed = %d kosu (v3b PENCERELI BCE)\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
cat("Varlik: THYAO.IS (gunluk) | class_weight: balanced\n")
cat("PENCERE: feats[(t-1):t]   (v3 vs v3b yan-yana karsilastirma icin)\n")
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

    yhat_stats_rows[[length(yhat_stats_rows) + 1]] <- data.frame(
      lambda = lam, seed = sd_seed,
      val_min = min(pred$yhat_val), val_max = max(pred$yhat_val),
      val_mean = mean(pred$yhat_val), val_sd = stats::sd(pred$yhat_val),
      test_min = min(pred$yhat_test), test_max = max(pred$yhat_test),
      test_mean = mean(pred$yhat_test), test_sd = stats::sd(pred$yhat_test),
      test_range = max(pred$yhat_test) - min(pred$yhat_test),
      stringsAsFactors = FALSE
    )

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

    for (thr in THRESHOLDS) {
      m_val  <- compute_metrics(y_va, pred$yhat_val,  thr)
      m_test <- compute_metrics(y_te, pred$yhat_test, thr)
      threshold_rows[[length(threshold_rows) + 1]] <- data.frame(
        lambda = lam, seed = sd_seed, threshold = thr,
        Acc_val = m_val$Acc, BalAcc_val = m_val$BalAcc, F1_val = m_val$F1,
        Sens_val = m_val$Sens, Spec_val = m_val$Spec,
        Acc_test = m_test$Acc, BalAcc_test = m_test$BalAcc, F1_test = m_test$F1,
        Sens_test = m_test$Sens, Spec_test = m_test$Spec,
        Acc_flip_test = m_test$Acc_flip,   # YENI: I.3 teshisi icin flip-Acc
        is_MC_test = m_test$is_MC,
        stringsAsFactors = FALSE
      )
    }

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
      test_Acc_flip_05 = m_test_05$Acc_flip,     # YENI flip-Acc kayit
      test_flip_beats_naive_05 = m_test_05$Acc_flip > naive_acc,
      test_is_MC_05 = m_test_05$is_MC,
      test_Acc_opt = m_test_best$Acc, test_Spec_opt = m_test_best$Spec,
      test_Sens_opt = m_test_best$Sens, test_BalAcc_opt = m_test_best$BalAcc,
      test_is_MC_opt = m_test_best$is_MC,
      stringsAsFactors = FALSE
    )

    cat(sprintf("  yhat (test): min=%.3f max=%.3f range=%.3f sd=%.3f\n",
                min(pred$yhat_test), max(pred$yhat_test),
                max(pred$yhat_test) - min(pred$yhat_test),
                stats::sd(pred$yhat_test)))
    cat(sprintf("  thr=0.50 -> Acc=%.3f Spec=%.3f Sens=%.3f Acc_flip=%.3f MC=%s\n",
                m_test_05$Acc, m_test_05$Spec, m_test_05$Sens,
                m_test_05$Acc_flip,
                if (m_test_05$is_MC) "YES" else "no"))
  }
}
t1 <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dakika\n",
            as.numeric(difftime(t1, t0, units = "mins"))))

# --- 11. Ozet ---
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
    Acc_flip_05 = mean(test_Acc_flip_05, na.rm = TRUE),
    flip_beats_naive_count = sum(test_flip_beats_naive_05, na.rm = TRUE),
    MC_05   = sum(test_is_MC_05, na.rm = TRUE),
    Acc_opt  = mean(test_Acc_opt, na.rm = TRUE),
    Spec_opt = mean(test_Spec_opt, na.rm = TRUE),
    Sens_opt = mean(test_Sens_opt, na.rm = TRUE),
    BalAcc_opt = mean(test_BalAcc_opt, na.rm = TRUE),
    MC_opt   = sum(test_is_MC_opt, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n", strrep("=", 95), "\n", sep = "")
cat("BiLSTM v3b WINDOW — OZET (ADIM I.4 LAG TUZAGI TESTI)\n")
cat(strrep("=", 95), "\n", sep = "")
cat(sprintf("\nVarlik: THYAO.IS | Veri: %d gunluk gozlem\n", nrow(thyao_final)))
cat(sprintf("Naive baseline: %.4f\n", naive_acc))
cat("\nMETRIK ozet (thr=0.5, v3 ile DOGRUDAN KARSILASTIRILABILIR):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05,
                             Acc_flip_05, flip_beats_naive_count, MC_05))

cat("\n", strrep("=", 95), "\n", sep = "")
cat("ADIM I.4 KARAR MATRISI\n")
cat(strrep("=", 95), "\n", sep = "")

mean_acc_05  <- mean(optimal_df$test_Acc_05, na.rm = TRUE)
mean_flip_05 <- mean(optimal_df$test_Acc_flip_05, na.rm = TRUE)
flip_wins    <- sum(optimal_df$test_flip_beats_naive_05, na.rm = TRUE)
n_cfg        <- nrow(optimal_df)

cat(sprintf("\n15 config ortalamasi:  Acc=%.3f  Acc_flip=%.3f  Naive=%.3f\n",
            mean_acc_05, mean_flip_05, naive_acc))
cat(sprintf("Flip-Acc Naive'i geciyor: %d / %d config\n", flip_wins, n_cfg))

cat("\nv3 KARSILASTIRMASI (referans, Bolum 10.18):\n")
cat("  v3 Acc=0.418 mean, Acc_flip=0.582 mean, 15/15 flip>naive (p=3e-5)\n")
cat("\nv3b SONUC ICIN HANGI DAL?\n")

if (mean_acc_05 >= 0.50 && flip_wins <= 7) {
  cat("[A] LAG TUZAGI DOGRULANDI:\n")
  cat("    Pencere duzeltilince Acc Naive seviyesine cikti, flip artik\n")
  cat("    galip degil. v3'teki 15/15 anti-prediktif TEKNIK ARTEFAKTI.\n")
  cat("    Yorum 3 (contrarian) MASADAN KALKAR. Yorum 1' guclu.\n")
  cat("    AKADEMIK BULGU: 'Yanlis pencereleme finans DL'inde sistematik\n")
  cat("    anti-prediktif davranisa yol acabilir.' Bu da bir keşif.\n")
} else if (mean_acc_05 < 0.45 && flip_wins >= 12) {
  cat("[B] LAG TUZAGI ELENDI, ANTI-PREDIKTIF GERCEK:\n")
  cat("    Pencere duzeltildi ama Acc hala Naive'in altinda + 15/15 flip\n")
  cat("    kazaniyor. v3'teki davranis MIMARI ARTEFAKT DEGIL.\n")
  cat("    Hipotezler (b)+(c) kalir: CW=balanced contrarian rejimi VE/VEYA\n")
  cat("    BIST gunluk reversal sinyali. Yorum 3 GUCLU — gercek anomali.\n")
} else if (abs(mean_acc_05 - 0.50) < 0.05) {
  cat("[C] RANDOM DAVRANIS:\n")
  cat("    Model duzeltilince Acc=0.50 civarinda. Sinyal yok/cok zayif.\n")
  cat("    Hem v3 hem v3b sonucu noisy; THYAO'da gunluk 3-gun-ileri tahmin\n")
  cat("    cok zor. Yorum 1' (rafine reframe) TEK gecerli yol.\n")
} else {
  cat("[?] BELIRSIZ:\n")
  cat(sprintf("    mean_acc=%.3f, flip_wins=%d/%d - matris disinda.\n",
              mean_acc_05, flip_wins, n_cfg))
  cat("    Manuel inceleme gerek; predictions CSV'sine bak.\n")
}

# CSV
out1 <- file.path(OUTDIR, "mcaware_BiLSTM_v3b_window_PREDICTIONS.csv")
out2 <- file.path(OUTDIR, "mcaware_BiLSTM_v3b_window_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR, "mcaware_BiLSTM_v3b_window_OPTIMAL.csv")
out4 <- file.path(OUTDIR, "mcaware_BiLSTM_v3b_window_SUMMARY.csv")
out5 <- file.path(OUTDIR, "mcaware_BiLSTM_v3b_window_YHAT_STATS.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)
write.csv(yhat_stats_df,  out5, row.names = FALSE)

cat("\n5 CSV kaydedildi:\n")
cat("  ", out1, "\n  ", out2, "\n  ", out3, "\n  ", out4, "\n  ", out5, "\n", sep = "")
cat("\nKRITIK SORULAR (I.4 icin):\n")
cat("1. Acc Naive'e ulasti mi? (v3'te 0.418 idi, hedef >=0.50 yani lag tuzagi)\n")
cat("2. 15/15 flip etkisi kirildi mi? (v3'te tum config flip > naive idi)\n")
cat("3. yhat dagilimi v3'e gore nasil degisti?\n")
cat("\nCSV'leri yukleyince Claude Bolum 10.22 olarak isleyecek.\n")

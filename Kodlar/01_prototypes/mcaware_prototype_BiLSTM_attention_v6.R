# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM + ATTENTION v6 (ADIM I.15)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026 — v3b_window'un ATTENTION KATMANI EKLENMIŞ kopyası
# ---------------------------------------------------------------------------
# NE FARKLI? (v3b → v6 farki)
#   v3b (orijinal): BiLSTM(return_sequences=FALSE) → Dropout → Dense(1)
#   v6  (bu):       BiLSTM(return_sequences=TRUE) → MultiHeadAttention(2 head)
#                   → Residual + LayerNorm → GlobalAvgPool → Dropout → Dense(1)
#
# Yani BiLSTM aynı, üstüne self-attention katmani eklendi.
# Transformer'dan ALINAN attention bloku (2 head, key_dim=32) BiLSTM
# cikisina baglanir. Boylece "BiLSTM + Attention" hipotezi test edilir.
#
# AMACI:
#   Orijinal Multi-Defense planinda "BiLSTM + Attention" vardi; multi_arch
#   ablasyonunda Attention SADECE Transformer icinde kullanildi. Hoca
#   sorabilir: "BiLSTM'e attention ekleseniz ne olurdu?" Cevap bu script.
#
#   Hipotez (a) ATTENTION REVERSAL'I KIRABILIR:
#     Attention "zaman icinde neye dikkat etmeli" ogrenir. Eger model
#     yanlis zaman adimina dikkat ettigi icin ters tahmin yapiyorsa,
#     attention bunu duzeltebilir → Acc > 0.50, flip_wins < 7.
#   Hipotez (b) ATTENTION ETKISIZ (mekanizma derinde):
#     Korelasyon kirilmasi feature uzayinda; attention zaman uzayinda
#     yardimci olmaz → v3b ile ayni sonuc: Acc < 0.45, flip 15/15.
#
# KARAR MATRISI:
#   [A] Acc_05 >= 0.50 + flip_wins <= 7  → ATTENTION CALISTI (surpriz!)
#       Yorum 3 zayiflar, "BiLSTM+Attention onerilir" pozitif sonuc.
#   [B] Acc_05 < 0.45 + flip_wins >= 12  → ATTENTION ETKISIZ
#       Yorum 3 GUCLENIR — mimari karmasikligi bile cozmuyor.
#   [C] Karisik/orta  → manuel inceleme
#
# CIKTI: v3b/multi_arch ile YAN-YANA KARSILASTIRMA icin ayni CSV formati.
#        5 CSV: PREDICTIONS, THRESHOLD_GRID, OPTIMAL, SUMMARY, YHAT_STATS.
#
# Calistirma: RStudio → Ctrl+Shift+S → ~45-60 dk → 5 CSV
# ===========================================================================

# --- 0. Ortam ---
WORKDIR <- "C:/Users/Kurt/Desktop"
OUTDIR  <- "C:/Users/Kurt/Desktop/Proje/00_Tubitak"
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
cat("MC-AWARE PROTOTYPE — BiLSTM + ATTENTION v6 (ADIM I.15)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("Mimari: BiLSTM(seq=TRUE) -> MHA(2 head) -> Res+LN -> GAP -> Dense\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR kullanilacak: ", WORKDIR)
  OUTDIR <- WORKDIR
}

# --- 0a. Bidirectional API tespiti (v3b ile aynı) ---
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

# --- 1. THYAO veri çekme (v3b ile AYNI) ---
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

# --- 2. Teknik göstergeler (v3b ile AYNI) ---
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

# Dış değişkenler (v3b ile AYNI)
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

# Birleştir
thyao_final <- thyao_df %>%
  left_join(usdtry_df, by = "Date") %>%
  left_join(oil_df, by = "Date") %>%
  left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")

thyao_final$USDTRY    <- zoo::na.locf(thyao_final$USDTRY, na.rm = FALSE)
thyao_final$Oil       <- zoo::na.locf(thyao_final$Oil, na.rm = FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm = FALSE)

thyao_final <- thyao_final[28:nrow(thyao_final), ]
thyao_final <- thyao_final %>% drop_na()
cat(sprintf("Final THYAO: %d satir\n", nrow(thyao_final)))

# --- 3. Pencereleme (v3b ile AYNI: anchor günü DAHIL) ---
IN_LEN  <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats  <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
cat(sprintf("Pencere sayisi: %d (In=%d, Out=%d, %d feature)\n",
            length(y_arr), IN_LEN, OUT_LEN, F_DIM))

# --- 4. Split (v3b ile AYNI) ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr+1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
X_te <- X_arr[(i_va+1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va+1L):n_total]
cat(sprintf("Split: Egitim=%d | Dogrulama=%d | Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))

n_up <- sum(y_tr == 1); n_down <- sum(y_tr == 0); n_train <- length(y_tr)
cw <- list("0" = n_train / (2 * n_down), "1" = n_train / (2 * n_up))
naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
cat(sprintf("NAIVE BASELINE: Acc = %.4f\n", naive_acc))

# --- 5. Normalization (v3b ile AYNI) ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 6. Loss (v3b ile AYNI: BCE + MC_Penalty) ---
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

# --- 7. BiLSTM + Attention mimarisi (FONKSIYONEL API) ***ASIL DEGISIKLIK*** ---
build_bilstm_attn <- function(seed, lambda_mc = 0.0) {
  keras3::set_random_seed(seed)

  # Input
  inp <- keras3::layer_input(shape = c(IN_LEN, F_DIM))

  # BiLSTM — return_sequences=TRUE (attention'a zaman dizisi besle)
  inner_lstm <- keras3::layer_lstm(units = 64, activation = "tanh",
                                    return_sequences = TRUE)
  x <- bidir_fn(inp, inner_lstm, merge_mode = "concat")
  # x boyutu: (batch, IN_LEN, 128)  -- BiLSTM 64+64 concat

  # Multi-Head Self-Attention (2 head, key_dim=32) — Transformer'dan alıntı
  attn_out <- keras3::layer_multi_head_attention(
    num_heads = 2, key_dim = 32)(x, x)

  # Residual + LayerNorm
  x <- keras3::layer_add(list(x, attn_out))
  x <- keras3::layer_layer_normalization()(x)

  # Global Average Pool (zaman ekseninde) → tek vektor
  x <- keras3::layer_global_average_pooling_1d()(x)
  x <- keras3::layer_dropout(rate = 0.4)(x)
  out <- keras3::layer_dense(units = 1, activation = "sigmoid")(x)

  model <- keras3::keras_model(inputs = inp, outputs = out)
  model %>% keras3::compile(
    optimizer = keras3::optimizer_adam(),
    loss = make_mc_loss(lambda_mc),
    metrics = c("accuracy")
  )
  model
}

# --- 8. Metrik (v3b ile AYNI) ---
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
  acc_flip <- 1 - acc
  list(Acc = acc, Sens = sens, Spec = spec, Prec = prec_,
       F1 = f1, BalAcc = bacc, is_MC = is_mc, Acc_flip = acc_flip,
       n_pred_Up = sum(pred), n_pred_Down = n - sum(pred))
}

# --- 9. Egit + tahmin ---
train_and_predict <- function(seed, lambda_mc) {
  keras3::clear_session()
  tryCatch({
    model <- build_bilstm_attn(seed, lambda_mc)
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

# --- 10. Grid (v3b ile AYNI: 3λ × 5 seed = 15 config) ---
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim: %d lambda x %d seed = %d kosu (BiLSTM+Attention)\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
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
        Acc_flip_test = m_test$Acc_flip,
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
      test_Acc_flip_05 = m_test_05$Acc_flip,
      test_flip_beats_naive_05 = m_test_05$Acc_flip > naive_acc,
      test_is_MC_05 = m_test_05$is_MC,
      test_Acc_opt = m_test_best$Acc, test_Spec_opt = m_test_best$Spec,
      test_Sens_opt = m_test_best$Sens, test_BalAcc_opt = m_test_best$BalAcc,
      test_is_MC_opt = m_test_best$is_MC,
      stringsAsFactors = FALSE
    )

    cat(sprintf("  yhat (test): min=%.3f max=%.3f range=%.3f\n",
                min(pred$yhat_test), max(pred$yhat_test),
                max(pred$yhat_test) - min(pred$yhat_test)))
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
    .groups = "drop"
  )

cat("\n", strrep("=", 95), "\n", sep = "")
cat("BiLSTM + ATTENTION v6 — OZET (ADIM I.15)\n")
cat(strrep("=", 95), "\n", sep = "")
cat(sprintf("\nVarlik: THYAO.IS | Veri: %d gunluk gozlem\n", nrow(thyao_final)))
cat(sprintf("Naive baseline: %.4f\n", naive_acc))
cat("\nMETRIK ozet (thr=0.5):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05,
                             Acc_flip_05, flip_beats_naive_count, MC_05))

cat("\n", strrep("=", 95), "\n", sep = "")
cat("KARSILASTIRMA (v3b vs v3c vs Transformer vs v6)\n")
cat(strrep("=", 95), "\n", sep = "")
cat("v3b (BiLSTM)        : Acc=0.396, Acc_flip=0.604, flip=15/15, MC=0\n")
cat("v3c (BiLSTM, CW=NULL): Acc=0.436, Acc_flip=0.564, flip=15/15, MC=0\n")
cat("Transformer (MHA)   : Acc=0.429, Acc_flip=0.571, flip=15/15, MC=0\n")

mean_acc_05  <- mean(optimal_df$test_Acc_05, na.rm = TRUE)
mean_flip_05 <- mean(optimal_df$test_Acc_flip_05, na.rm = TRUE)
flip_wins    <- sum(optimal_df$test_flip_beats_naive_05, na.rm = TRUE)
n_cfg        <- nrow(optimal_df)
mc_count     <- sum(optimal_df$test_is_MC_05, na.rm = TRUE)

cat(sprintf("v6 (BiLSTM+Attn)    : Acc=%.3f, Acc_flip=%.3f, flip=%d/%d, MC=%d\n",
            mean_acc_05, mean_flip_05, flip_wins, n_cfg, mc_count))

cat("\n", strrep("=", 95), "\n", sep = "")
cat("KARAR MATRISI (ADIM I.15)\n")
cat(strrep("=", 95), "\n", sep = "")

if (mean_acc_05 >= 0.50 && flip_wins <= 7) {
  cat("[A] ATTENTION CALISTI - SURPRIZ!:\n")
  cat(sprintf("    Acc=%.3f >= 0.50, flip=%d/%d <= 7\n",
              mean_acc_05, flip_wins, n_cfg))
  cat("    BiLSTM'e attention eklemek reversal'i KIRDI.\n")
  cat("    Yorum 3 zayiflar - 'mimari karmasikligi cozer' yeni iddiasi.\n")
  cat("    TUBITAK icin POZITIF: 'BiLSTM+Attention sistematik anti-prediktif\n")
  cat("    davranisi cozen tek mimari oldu.'\n")
} else if (mean_acc_05 < 0.45 && flip_wins >= 12) {
  cat("[B] ATTENTION ETKISIZ (BEKLENEN):\n")
  cat(sprintf("    Acc=%.3f < 0.45, flip=%d/%d >= 12\n",
              mean_acc_05, flip_wins, n_cfg))
  cat("    Attention da reversal'i KIRAMADI.\n")
  cat("    Yorum 3 GUCLENIR: mekanizma feature uzayinda (korelasyon\n")
  cat("    kirilmasi), zaman uzayinda attention yardimci olmaz.\n")
  cat("    TUBITAK icin GUCLU: '7. mimari (BiLSTM+Attention) da anti-prediktif\n")
  cat("    → mimari-bagimsizlik iddia ZAYIFLAMADI, daha da kuvvetlendi.'\n")
} else if (mean_acc_05 >= 0.45 && mean_acc_05 < 0.50) {
  cat("[C] ORTA - ATTENTION KISMI ETKILI:\n")
  cat(sprintf("    Acc=%.3f, flip=%d/%d\n", mean_acc_05, flip_wins, n_cfg))
  cat("    Attention etkiyi azaltti ama bitirmedi. Manuel inceleme gerek.\n")
} else {
  cat("[?] BELIRSIZ:\n")
  cat(sprintf("    mean_acc=%.3f, flip_wins=%d/%d - matris disinda.\n",
              mean_acc_05, flip_wins, n_cfg))
}

# --- 12. CSV cikti ---
out1 <- file.path(OUTDIR, "mcaware_BiLSTM_attn_v6_PREDICTIONS.csv")
out2 <- file.path(OUTDIR, "mcaware_BiLSTM_attn_v6_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR, "mcaware_BiLSTM_attn_v6_OPTIMAL.csv")
out4 <- file.path(OUTDIR, "mcaware_BiLSTM_attn_v6_SUMMARY.csv")
out5 <- file.path(OUTDIR, "mcaware_BiLSTM_attn_v6_YHAT_STATS.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)
write.csv(yhat_stats_df,  out5, row.names = FALSE)

cat("\n5 CSV kaydedildi:\n")
cat("  ", out1, "\n  ", out2, "\n  ", out3, "\n  ", out4, "\n  ", out5, "\n", sep = "")
cat("\nCSV'leri yukleyince Claude Bolum 10.36 (ADIM I.15) olarak isleyecek.\n")

# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM v3c NO CW (ADIM I.7: CW ABLATION)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 22.05.2026 — v3b'nin CW=NULL ablation kopyasi
# ---------------------------------------------------------------------------
# AMACI:
#   v3 + v3b'de THYAO test setinde 30/30 anti-prediktif gozlendi
#   (p ~ 3e-5). Iki hipotez ayirt edilmedi:
#     (b) CW=balanced'in contrarian artefakti — model gradient'i ters
#         yone itiyor olabilir
#     (c) Gercek BIST gunluk reversal sinyali — Jegadeesh-Titman tipi
#
#   v3c bu testi yapar: v3b ile TAMAMEN ayni, SADECE class_weight = NULL.
#   Tum diger parametreler (mimari, pencere, seed, lambda, threshold,
#   normalization) v3b ile birebir esit.
#
# KARAR MATRISI:
#   [I] NO CW'de flip_wins >= 12/15  → Anti-prediktif CW'den BAGIMSIZ.
#                                       Hipotez (b) ELENDI; (c) gercek
#                                       sinyal kalir. Yorum 3 PEKIYI
#                                       GUCLU. CW etiketten cikartilabilir
#                                       (ama o zaman MC tuzagi geri doner —
#                                       trade-off net olur).
#
#   [II] NO CW'de flip_wins <= 7/15  → Anti-prediktif CW=balanced'a BAGIMLI.
#                                      Hipotez (b) DOGRULANDI. Anti-prediktif
#                                      "CW kaynakli mimari artefakt"
#                                      Yorum 3 yikici darbe alir; Yorum 1'
#                                      one cikar. Aksiyon: literatur
#                                      taramasi (CW + sequence model
#                                      gradient inversion).
#
#   [III] NO CW'de Acc >= 0.55       → BONUS: CW olmadan model GERCEKTEN
#                                      tahmin yapiyor (Naive 0.518). Bu
#                                      durumda Yorum 2 (MC + iyi Acc)
#                                      kismi destek alabilir. AMA: MC
#                                      tuzagi geri donerse (Spec~0 ya da
#                                      Sens~0) iddia tek-sinif tahmine
#                                      dayanir, dikkatli yazilmali.
#
# CIKTI: v3b ile yan-yana karsilastirma icin AYNI CSV formati.
#        5 CSV: PREDICTIONS, THRESHOLD_GRID, OPTIMAL, SUMMARY, YHAT_STATS.
#
# Calistirma: RStudio → Ctrl+Shift+S → ~30-45 dk → 5 CSV
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
cat("MC-AWARE PROTOTYPE — BiLSTM v3c NO CW (ADIM I.7 CW ABLATION)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Cikti klasoru:", OUTDIR, "\n")
cat("v3b'den TEK FARK: class_weight = NULL\n")
cat("========================================================================\n\n")

if (!dir.exists(OUTDIR)) {
  warning("Cikti klasoru yok, WORKDIR'a kayit: ", WORKDIR)
  OUTDIR <- WORKDIR
}

# --- 0a. Bidirectional API tespiti ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
} else {
  stop("keras3 bidirectional bulunamadi.")
}

# --- 1. THYAO veri cekme (v3b ile AYNI) ---
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

# Teknik gostergeler (v3b ile AYNI)
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

# Dis degiskenler (v3b ile AYNI)
tryCatch({
  getSymbols("USDTRY=X", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  usdtry_df <- data.frame(
    Date   = as.character(index(`USDTRY=X`)),
    USDTRY = as.numeric(Cl(`USDTRY=X`))
  )
}, error = function(e) {
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
  tcmb_daily <<- data.frame(Date = as.Date(thyao_df$Date),
                             TCMB_Rate = NA_real_)
})

thyao_final <- thyao_df %>%
  left_join(usdtry_df, by = "Date") %>%
  left_join(oil_df, by = "Date") %>%
  left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")
thyao_final$USDTRY    <- zoo::na.locf(thyao_final$USDTRY, na.rm = FALSE)
thyao_final$Oil       <- zoo::na.locf(thyao_final$Oil, na.rm = FALSE)
thyao_final$TCMB_Rate <- zoo::na.locf(thyao_final$TCMB_Rate, na.rm = FALSE)
thyao_final <- thyao_final[28:nrow(thyao_final), ] %>% drop_na()
cat(sprintf("Final THYAO: %d satir\n", nrow(thyao_final)))

# --- 2. Pencereleme (v3b ile AYNI - anchor gunu DAHIL) ---
IN_LEN  <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats <- as.matrix(thyao_final[, feat_cols])
prices <- thyao_final$Close
N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
cat(sprintf("Pencere sayisi: %d\n", length(y_arr)))

# --- 3. Split (v3b ile AYNI) ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr+1L):i_va, , , drop = FALSE]; y_va <- y_arr[(i_tr+1L):i_va]
X_te <- X_arr[(i_va+1L):n_total, , , drop = FALSE]; y_te <- y_arr[(i_va+1L):n_total]
cat(sprintf("Split: Train=%d Val=%d Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))
cat(sprintf("Train Up=%%%.1f Val Up=%%%.1f Test Up=%%%.1f\n",
            100*mean(y_tr), 100*mean(y_va), 100*mean(y_te)))

# *** KRITIK FARK: class_weight = NULL (egitim sirasinda kullanilmayacak) ***
cat("\n*** class_weight = NULL (v3b ile TEK FARK) ***\n")
cat("v3b'de balanced CW vardi; burada model duz BCE ile egitilecek.\n\n")

naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
cat(sprintf("NAIVE BASELINE: Acc = %.4f\n", naive_acc))

# --- 4. Normalize (v3b ile AYNI) ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 5. Loss + model (v3b ile AYNI) ---
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
build_bilstm <- function(seed, lambda_mc) {
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

# --- 6. Metrik (v3b ile AYNI) ---
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

# --- 7. Train + predict (KRITIK FARK: class_weight ARGUMANI VERILMIYOR) ---
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
      callbacks = list(cb)
      # NOT: class_weight arguman VERILMIYOR - bu v3b'den TEK FARK
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

# --- 8. Grid (v3b ile AYNI) ---
SEEDS      <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS    <- c(0.0, 0.05, 0.10)
THRESHOLDS <- seq(0.30, 0.70, by = 0.05)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("Egitim: %d lambda x %d seed = %d kosu (v3c NO CW)\n",
            length(LAMBDAS), length(SEEDS), length(LAMBDAS) * length(SEEDS)))
cat("Varlik: THYAO.IS | class_weight: NULL (ablation)\n")
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
    if (!is.na(pred$error)) { cat(" HATA:", pred$error, "\n"); next }

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
    best_thr <- THRESHOLDS[which.max(val_bacc)]
    m_val_best  <- compute_metrics(y_va, pred$yhat_val,  best_thr)
    m_test_best <- compute_metrics(y_te, pred$yhat_test, best_thr)
    m_test_05   <- compute_metrics(y_te, pred$yhat_test, 0.5)

    optimal_rows[[length(optimal_rows) + 1]] <- data.frame(
      lambda = lam, seed = sd_seed, best_thr = best_thr,
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

# --- 9. Ozet ---
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
    MC_05 = sum(test_is_MC_05, na.rm = TRUE),
    Acc_opt  = mean(test_Acc_opt, na.rm = TRUE),
    Spec_opt = mean(test_Spec_opt, na.rm = TRUE),
    Sens_opt = mean(test_Sens_opt, na.rm = TRUE),
    BalAcc_opt = mean(test_BalAcc_opt, na.rm = TRUE),
    MC_opt = sum(test_is_MC_opt, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n", strrep("=", 95), "\n", sep = "")
cat("BiLSTM v3c NO CW — OZET (ADIM I.7 CW ABLATION)\n")
cat(strrep("=", 95), "\n", sep = "")
cat(sprintf("\nVarlik: THYAO.IS | Naive baseline: %.4f\n", naive_acc))
cat("\nMETRIK ozet (thr=0.5):\n")
print(summary_df %>% select(lambda, Acc_05, Spec_05, Sens_05, BalAcc_05,
                             Acc_flip_05, flip_beats_naive_count, MC_05))

# --- 10. KARAR MATRISI ---
cat("\n", strrep("=", 95), "\n", sep = "")
cat("ADIM I.7 KARAR MATRISI\n")
cat(strrep("=", 95), "\n", sep = "")
mean_acc_05  <- mean(optimal_df$test_Acc_05, na.rm = TRUE)
mean_flip_05 <- mean(optimal_df$test_Acc_flip_05, na.rm = TRUE)
flip_wins    <- sum(optimal_df$test_flip_beats_naive_05, na.rm = TRUE)
mc_count     <- sum(optimal_df$test_is_MC_05, na.rm = TRUE)
n_cfg        <- nrow(optimal_df)

cat(sprintf("\nv3c NO CW (15 config ortalamasi):\n"))
cat(sprintf("  Acc=%.3f  Acc_flip=%.3f  Naive=%.3f  flip_wins=%d/%d  MC=%d/%d\n",
            mean_acc_05, mean_flip_05, naive_acc, flip_wins, n_cfg, mc_count, n_cfg))
cat("\nKARSILASTIRMA REFERANSI:\n")
cat("  v3b (CW=balanced): Acc=0.396 flip=0.604 flip_wins=15/15 MC=0/15\n")
cat("  v3  (CW=balanced): Acc=0.418 flip=0.582 flip_wins=15/15 MC=0/15\n\n")

if (mc_count >= 12) {
  cat("[II-A] CW kaldirilinca MC TUZAGINA GERI DONULDU (beklenen):\n")
  cat(sprintf("       %d/15 config MC. Anti-prediktif sorgulanmadi cunku model\n", mc_count))
  cat("       sabit tahmin yapiyor. CW'nin gerekliligini DOGRULAR.\n")
  cat("       Asil soru CW VAR iken hala sorulu: anti-prediktif gercek mi?\n")
} else if (flip_wins >= 12 && mc_count <= 5) {
  cat("[I] ANTI-PREDIKTIF CW'DEN BAGIMSIZ:\n")
  cat("    NO CW'de de flip_beats_naive devam ediyor. Hipotez (b) CW\n")
  cat("    artefakti ELENDI. Yorum 3 (contrarian/reversal) GUCLENDI.\n")
  cat("    Anti-prediktif CW'ye bagimli degil, daha derin bir veri ozelligi.\n")
} else if (flip_wins <= 7 && mean_acc_05 >= 0.45) {
  cat("[II-B] ANTI-PREDIKTIF CW'YE BAGIMLI:\n")
  cat("       NO CW'de flip kazanmiyor. Hipotez (b) DOGRULANDI: anti-prediktif\n")
  cat("       CW=balanced gradient-inversion artefakti. Yorum 3 zayifladi,\n")
  cat("       Yorum 1' one cikar.\n")
} else if (mean_acc_05 >= 0.55) {
  cat("[III] BONUS: NO CW model gercekten tahmin yapiyor (Acc >= 0.55):\n")
  cat("      Yorum 2 (klasik basari) destek alir. AMA MC kontrolu:\n")
  cat(sprintf("      MC sayisi=%d/15 - eger yuksekse, Acc artisi MC kaynakli.\n", mc_count))
} else {
  cat("[?] BELIRSIZ:\n")
  cat(sprintf("    mean_acc=%.3f flip_wins=%d/%d MC=%d/%d\n",
              mean_acc_05, flip_wins, n_cfg, mc_count, n_cfg))
  cat("    Manuel inceleme gerek; threshold grid'e bak.\n")
}

# CSV
out1 <- file.path(OUTDIR, "mcaware_BiLSTM_v3c_no_cw_PREDICTIONS.csv")
out2 <- file.path(OUTDIR, "mcaware_BiLSTM_v3c_no_cw_THRESHOLD_GRID.csv")
out3 <- file.path(OUTDIR, "mcaware_BiLSTM_v3c_no_cw_OPTIMAL.csv")
out4 <- file.path(OUTDIR, "mcaware_BiLSTM_v3c_no_cw_SUMMARY.csv")
out5 <- file.path(OUTDIR, "mcaware_BiLSTM_v3c_no_cw_YHAT_STATS.csv")
write.csv(predictions_df, out1, row.names = FALSE)
write.csv(threshold_df,   out2, row.names = FALSE)
write.csv(optimal_df,     out3, row.names = FALSE)
write.csv(summary_df,     out4, row.names = FALSE)
write.csv(yhat_stats_df,  out5, row.names = FALSE)
cat("\n5 CSV kaydedildi.\n")
cat("\nADIM I.7 TAMAMLANDI — sonuclari PROJE_DURUMU.txt Bolum 10.28 olarak isle.\n")

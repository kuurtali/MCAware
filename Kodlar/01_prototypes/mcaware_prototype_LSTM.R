# ===========================================================================
# MC-AWARE PROTOTYPE — LSTM (R + keras3)
# TÜBİTAK 2209-A Ön Kanıt Çalışması (Mehmet Ali Kurt, yürütücü)
# ---------------------------------------------------------------------------
# Amaç:
#   AMZ LSTM full/In=2/Out=3 şampiyon konfigürasyonu üzerinde MC_Penalty
#   teriminin etkisini ölçmek.
#
# Karşılaştırma:
#   Vanilla BCE  vs  BCE + λ·|mean(ŷ)−0.5|   (λ ∈ {0.0, 0.1, 0.3, 0.5})
#   3 seed: 23, 27, 98 (mevcut çalışmayla aynı)
#
# Çalıştırma:
#   1) RStudio'da bu dosyayı aç.
#   2) setwd() yolunu kontrol et (mevcut EMEKLILIK_GUNCEL.R ile aynı).
#   3) Source > Run All
#   4) Çıktı: mcaware_LSTM_RESULTS.csv (özet) + konsol tablosu
#
# Süre: CPU modunda yaklaşık 30-60 dakika (12 koşu × ~3-5 dakika)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ---
setwd("here::here()")  # senin EMEKLILIK_GUNCEL.R'daki ile aynı
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")  # GPU bypass (RTX 5050)

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(caret)
  library(zoo)
  library(keras3)
  library(tensorflow)
  library(readxl)
})

# --- 1. Veri ---
raw <- read_excel("ALZ_AZS_AMZ_Haftalik.xlsx")
raw <- raw[!is.na(raw$Date), ]
colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                    "Price_AZS", "LogReturn_AZS",
                    "Price_AMZ", "LogReturn_AMZ")
for (c in c("Price_AMZ", "LogReturn_AMZ")) raw[[c]] <- as.numeric(raw[[c]])
amz <- raw %>% filter(!is.na(Price_AMZ)) %>% select(Date, Close = Price_AMZ)

# --- 2. Özellik mühendisliği (full set, TEFAS proxies) ---
amz$RSI       <- TTR::RSI(amz$Close, n = 14)
ema12         <- TTR::EMA(amz$Close, n = 12)
ema26         <- TTR::EMA(amz$Close, n = 26)
amz$MACD      <- ema12 - ema26
amz$EMA12     <- ema12
amz$EMA26     <- ema26
amz$Momentum  <- amz$Close / lag(amz$Close, 14) - 1
amz$Volatility <- zoo::rollapply(c(NA, diff(log(amz$Close))),
                                  width = 14, FUN = sd,
                                  fill = NA, align = "right")
amz <- amz %>% drop_na()
cat(sprintf("AMZ veri (warmup sonrası): %d hafta\n", nrow(amz)))

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
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L - 1L):(t - 1L), , drop = FALSE]
  # Yukarıdaki: t = mevcut nokta. Pencere = t-IN_LEN .. t-1 (geçmiş IN_LEN hafta).
  # Etiket: P_{t+OUT_LEN} > P_t  ?  1 : 0
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
cat(sprintf("Toplam pencere: %d | sınıf Up=%%%.1f\n",
            length(y_arr), 100 * mean(y_arr)))

# --- 4. Split (70/15/15 kronolojik) ---
n_total <- length(y_arr)
i_tr <- floor(n_total * 0.70)
i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]
y_tr <- y_arr[1:i_tr]
X_va <- X_arr[(i_tr + 1L):i_va, , , drop = FALSE]
y_va <- y_arr[(i_tr + 1L):i_va]
X_te <- X_arr[(i_va + 1L):n_total, , , drop = FALSE]
y_te <- y_arr[(i_va + 1L):n_total]

cat(sprintf("Split: Eğitim=%d | Doğrulama=%d | Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))
cat(sprintf("Test Up=%%%.1f (Up=%d, Down=%d)\n",
            100 * mean(y_te), sum(y_te), length(y_te) - sum(y_te)))

# --- 5. Train-only normalization (data leakage önleme) ---
mu <- apply(X_tr, c(2,3), mean)
sd <- apply(X_tr, c(2,3), sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu, "-"), c(2,3), sd, "/")
X_tr <- normalize(X_tr); X_va <- normalize(X_va); X_te <- normalize(X_te)

# --- 6. MC-Aware Loss (custom Keras loss) ---
make_mc_aware_loss <- function(lambda) {
  function(y_true, y_pred) {
    bce <- keras3::loss_binary_crossentropy(y_true, y_pred)
    mean_pred <- keras3::op_mean(y_pred)
    mc_penalty <- keras3::op_abs(mean_pred - 0.5)
    bce + lambda * mc_penalty
  }
}

# --- 7. Model fabrikası (AMZ şampiyonu HP: adam / tanh / dropout=0.4) ---
build_lstm <- function(seed, lambda_mc = 0.0) {
  keras3::set_random_seed(seed)
  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM)) %>%
    keras3::layer_lstm(units = 64, activation = "tanh", return_sequences = FALSE) %>%
    keras3::layer_dropout(0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")

  # class weight (AMZ sınıf dengesizliği için)
  cw <- list("0" = length(y_tr) / (2 * sum(y_tr == 0)),
             "1" = length(y_tr) / (2 * sum(y_tr == 1)))

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

# --- 8. Eğitim + değerlendirme ---
train_eval <- function(seed, lambda_mc) {
  bundle <- build_lstm(seed, lambda_mc)
  cb <- keras3::callback_early_stopping(monitor = "val_accuracy",
                                         patience = 5L,
                                         restore_best_weights = TRUE)
  bundle$model %>% keras3::fit(
    X_tr, y_tr,
    validation_data = list(X_va, y_va),
    epochs = 50L, batch_size = 16L, verbose = 0L,
    callbacks = list(cb), class_weight = bundle$class_weight
  )
  yhat <- as.numeric(predict(bundle$model, X_te, verbose = 0L))
  pred <- as.integer(yhat > 0.5)
  tp <- sum(pred == 1 & y_te == 1)
  tn <- sum(pred == 0 & y_te == 0)
  fp <- sum(pred == 1 & y_te == 0)
  fn <- sum(pred == 0 & y_te == 1)
  acc  <- (tp + tn) / length(y_te)
  sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) ||
           is.na(spec) || is.na(sens)
  list(Acc = acc, Sens = sens, Spec = spec, mean_yhat = mean(yhat),
       n_pred_Up = sum(pred), n_pred_Down = length(pred) - sum(pred),
       is_MC = is_mc)
}

# --- 9. Grid: λ × seed ---
SEEDS <- c(23L, 27L, 98L)
LAMBDAS <- c(0.0, 0.1, 0.3, 0.5)

cat("\n", strrep("=", 85), "\n", sep = "")
cat(sprintf("AMZ — full / In=%d / Out=%d — LSTM MC_Penalty Grid\n", IN_LEN, OUT_LEN))
cat(strrep("=", 85), "\n", sep = "")
cat(sprintf("%5s | %4s | %6s | %6s | %6s | %8s | %4s | %4s | %3s\n",
            "lambda", "seed", "Acc", "Sens", "Spec", "mean", "#Up", "#Dn", "MC?"))
cat(strrep("-", 85), "\n", sep = "")

results <- list()
for (lam in LAMBDAS) {
  for (sd_ in SEEDS) {
    cat(sprintf("Koşuluyor: λ=%.1f seed=%d ...\n", lam, sd_))
    res <- train_eval(sd_, lam)
    results[[length(results) + 1]] <- c(list(lambda = lam, seed = sd_), res)
    cat(sprintf("%5.1f | %4d | %6.4f | %6.4f | %6.4f | %8.4f | %4d | %4d | %3s\n",
                lam, sd_, res$Acc,
                ifelse(is.na(res$Sens), NA, res$Sens),
                ifelse(is.na(res$Spec), NA, res$Spec),
                res$mean_yhat, res$n_pred_Up, res$n_pred_Down,
                if (res$is_MC) "YES" else "no"))
  }
}

# --- 10. Özet ---
df_res <- do.call(rbind, lapply(results, as.data.frame))
cat("\n", strrep("=", 85), "\n", sep = "")
cat("ÖZET — λ başına 3-seed ortalaması\n")
cat(strrep("=", 85), "\n", sep = "")

summary_tbl <- df_res %>%
  group_by(lambda) %>%
  summarise(Acc_m = mean(Acc), Acc_sd = sd(Acc),
            Sens_m = mean(Sens, na.rm = TRUE), Sens_sd = sd(Sens, na.rm = TRUE),
            Spec_m = mean(Spec, na.rm = TRUE), Spec_sd = sd(Spec, na.rm = TRUE),
            mean_yhat_m = mean(mean_yhat), MC_count = sum(is_MC), .groups = "drop")
print(summary_tbl)

# CSV çıktısı
write.csv(df_res, "mcaware_LSTM_RESULTS.csv", row.names = FALSE)
write.csv(summary_tbl, "mcaware_LSTM_SUMMARY.csv", row.names = FALSE)
cat("\nCSV'ler kaydedildi: mcaware_LSTM_RESULTS.csv ve mcaware_LSTM_SUMMARY.csv\n")
cat("Bu CSV'leri benimle paylaşırsan strateji dosyasına 'ön kanıt' olarak işleyeceğim.\n")

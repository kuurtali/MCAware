# ===========================================================================
# MC-AWARE PROTOTYPE — BiLSTM (R + keras3) — v1.1 (hatasız sürüm)
# TÜBİTAK 2209-A Ön Kanıt Çalışması
# Yürütücü: Mehmet Ali Kurt | Danışman: Övgücan KARADAĞ ERDEMİR
# Tarih: 19.05.2026 (Bölüm 11.4 hoca onayı sonrası — BiLSTM hattı)
# ---------------------------------------------------------------------------
# DEĞİŞİKLİK (v1.1 vs v1):
#   [+] keras3::bidirectional / layer_bidirectional otomatik tespit (fallback)
#   [+] Her iterasyonda keras3::clear_session() — bellek sızıntısı önleme
#   [+] Veri dosyası varlık kontrolü
#   [+] try/catch ile koşu hatalarına karşı güvenlik
#   [+] Çıktı kayıt yolu mutlak (kullanıcı setwd dışında çalıştırsa bile çalışır)
#
# Karşılaştırma:
#   Vanilla BCE  vs  BCE + λ·|mean(ŷ)−0.5|   (λ ∈ {0.0, 0.1, 0.3, 0.5})
#   5 seed: 23, 27, 98, 41, 64  (eski 3 seed'e ek 2)
#
# Çalıştırma:
#   1) RStudio'da bu dosyayı aç
#   2) Source > Run All (Ctrl+Shift+S)
#   3) ~50-90 dakika bekle (CPU modunda)
#   4) Üretilen 3 CSV'yi Cowork'e geri yükle
#
# Çıktı dosyaları (here::here()/ altında):
#   - mcaware_BiLSTM_v1_RESULTS.csv      (20 satır ham)
#   - mcaware_BiLSTM_v1_SUMMARY.csv      (4 satır lambda özet)
#   - mcaware_BiLSTM_v1_SEED_REPORT.csv  (5 satır seed dirençlilik)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


# --- 0. Ortam ayarları ---
WORKDIR    <- here::here()
setwd(WORKDIR)
OUTDIR_SUM  <- here::here("Sonuclar", "summaries")
OUTDIR_DIAG <- here::here("Sonuclar", "diagnostics")
Sys.setenv(CUDA_VISIBLE_DEVICES = "-1")     # GPU bypass (RTX 5050 keras3 sorunu)
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = "3")      # TF gürültüsünü kapat
Sys.setenv(TF_ENABLE_ONEDNN_OPTS = "0")     # oneDNN deterministiklik

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(keras3)
  library(tensorflow)
  library(readxl)
})

cat("\n========================================================================\n")
cat("MC-AWARE PROTOTYPE — BiLSTM v1.1  (AMZ full / In=2 / Out=3)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("R sürümü:", R.version.string, "\n")
cat("keras3 sürümü:", as.character(packageVersion("keras3")), "\n")
cat("========================================================================\n\n")

# --- 0a. Bidirectional API tespiti (keras3 sürüm uyumluluğu) ---
.ns <- asNamespace("keras3")
if (exists("bidirectional", envir = .ns)) {
  bidir_fn <- get("bidirectional", envir = .ns)
  cat("Bidirectional API: keras3::bidirectional()\n")
} else if (exists("layer_bidirectional", envir = .ns)) {
  bidir_fn <- get("layer_bidirectional", envir = .ns)
  cat("Bidirectional API: keras3::layer_bidirectional() (eski isim)\n")
} else {
  stop("HATA: keras3 paketinde bidirectional/layer_bidirectional bulunamadi. ",
       "keras3'u guncelle: install.packages('keras3'); keras3::install_keras()")
}

# --- 0b. Veri dosyası varlık kontrolü ---
DATA_FILE <- file.path(WORKDIR, "ALZ_AZS_AMZ_Haftalik.xlsx")
if (!file.exists(DATA_FILE)) {
  stop("HATA: Veri dosyasi bulunamadi: ", DATA_FILE,
       "\n   Lutfen ALZ_AZS_AMZ_Haftalik.xlsx dosyasini ", WORKDIR, " icine koy.")
}

# --- 1. Veri yükleme ---
raw <- read_excel(DATA_FILE)
raw <- raw[!is.na(raw$Date), ]
colnames(raw) <- c("Date", "Price_ALZ", "LogReturn_ALZ",
                    "Price_AZS", "LogReturn_AZS",
                    "Price_AMZ", "LogReturn_AMZ")
for (c_ in c("Price_AMZ", "LogReturn_AMZ")) raw[[c_]] <- as.numeric(raw[[c_]])
amz <- raw %>% filter(!is.na(Price_AMZ)) %>% select(Date, Close = Price_AMZ)

# --- 2. Özellik mühendisliği (full set) ---
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
cat(sprintf("Toplam pencere: %d | sinif Up=%%%.1f\n",
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

cat(sprintf("Split: Egitim=%d | Dogrulama=%d | Test=%d\n",
            length(y_tr), length(y_va), length(y_te)))
cat(sprintf("Test Up=%%%.1f (Up=%d, Down=%d)\n",
            100 * mean(y_te), sum(y_te), length(y_te) - sum(y_te)))

# --- 5. Train-only normalization (data leakage onleme) ---
mu_arr <- apply(X_tr, c(2,3), mean)
sd_arr <- apply(X_tr, c(2,3), stats::sd) + 1e-8
normalize <- function(A) sweep(sweep(A, c(2,3), mu_arr, "-"), c(2,3), sd_arr, "/")
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

# --- 7. Model fabrikasi — BiLSTM (hoca onayi 19.05.2026) ---
build_bilstm <- function(seed, lambda_mc = 0.0) {
  keras3::set_random_seed(seed)

  inner_lstm <- keras3::layer_lstm(
    units = 64, activation = "tanh", return_sequences = FALSE
  )

  model <- keras3::keras_model_sequential(input_shape = c(IN_LEN, F_DIM))
  model <- bidir_fn(model, inner_lstm, merge_mode = "concat")
  model <- model %>%
    keras3::layer_dropout(rate = 0.4) %>%
    keras3::layer_dense(units = 1, activation = "sigmoid")

  # class weight (AMZ sinif dengesizligi)
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

# --- 8. Egitim + degerlendirme (try/catch ile guvenli) ---
train_eval <- function(seed, lambda_mc) {
  keras3::clear_session()  # Onceki modelin bellegini temizle
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
         is_MC = is_mc, error = NA_character_)
  }, error = function(e) {
    list(Acc = NA_real_, Sens = NA_real_, Spec = NA_real_, mean_yhat = NA_real_,
         n_pred_Up = NA_integer_, n_pred_Down = NA_integer_,
         is_MC = NA, error = conditionMessage(e))
  })
  result
}

# --- 9. Grid: lambda x seed (5 seed) ---
SEEDS   <- c(23L, 27L, 98L, 41L, 64L)
LAMBDAS <- c(0.0, 0.1, 0.3, 0.5)

cat("\n", strrep("=", 95), "\n", sep = "")
cat(sprintf("AMZ — full / In=%d / Out=%d — BiLSTM MC_Penalty Grid (4 lambda x 5 seed = 20 kosu)\n",
            IN_LEN, OUT_LEN))
cat(strrep("=", 95), "\n", sep = "")
cat(sprintf("%6s | %4s | %6s | %6s | %6s | %8s | %4s | %4s | %3s\n",
            "lambda", "seed", "Acc", "Sens", "Spec", "mean", "#Up", "#Dn", "MC?"))
cat(strrep("-", 95), "\n", sep = "")

results <- list()
t0 <- Sys.time()
for (lam in LAMBDAS) {
  for (sd_seed in SEEDS) {
    cat(sprintf("Kosuluyor: lambda=%.1f seed=%d ...\n", lam, sd_seed))
    res <- train_eval(sd_seed, lam)
    results[[length(results) + 1]] <- c(list(lambda = lam, seed = sd_seed), res)
    if (!is.na(res$error)) {
      cat(sprintf("  HATA: %s\n", res$error))
    } else {
      cat(sprintf("%6.1f | %4d | %6.4f | %6.4f | %6.4f | %8.4f | %4d | %4d | %3s\n",
                  lam, sd_seed, res$Acc,
                  ifelse(is.na(res$Sens), NA, res$Sens),
                  ifelse(is.na(res$Spec), NA, res$Spec),
                  res$mean_yhat, res$n_pred_Up, res$n_pred_Down,
                  if (isTRUE(res$is_MC)) "YES" else "no"))
    }
  }
}
t1 <- Sys.time()
cat(sprintf("\nToplam sure: %.1f dakika\n",
            as.numeric(difftime(t1, t0, units = "mins"))))

# --- 10. Ozet ---
df_res <- do.call(rbind, lapply(results, function(r) {
  as.data.frame(r, stringsAsFactors = FALSE)
}))
cat("\n", strrep("=", 95), "\n", sep = "")
cat("OZET — lambda basina 5-seed ortalamasi (BiLSTM)\n")
cat(strrep("=", 95), "\n", sep = "")

summary_tbl <- df_res %>%
  group_by(lambda) %>%
  summarise(Acc_m = mean(Acc, na.rm = TRUE),
            Acc_sd = stats::sd(Acc, na.rm = TRUE),
            Sens_m = mean(Sens, na.rm = TRUE),
            Sens_sd = stats::sd(Sens, na.rm = TRUE),
            Spec_m = mean(Spec, na.rm = TRUE),
            Spec_sd = stats::sd(Spec, na.rm = TRUE),
            mean_yhat_m = mean(mean_yhat, na.rm = TRUE),
            MC_count = sum(is_MC, na.rm = TRUE),
            n = dplyr::n(),
            .groups = "drop")
print(summary_tbl)

# --- 11. Seed bazinda MC vakasi raporu ---
cat("\nSeed basina MC durumu (lambda ortalamasi):\n")
seed_mc <- df_res %>%
  group_by(seed) %>%
  summarise(n_MC = sum(is_MC, na.rm = TRUE),
            n_total = dplyr::n(),
            mean_Spec = mean(Spec, na.rm = TRUE),
            .groups = "drop")
print(seed_mc)

cat("\nYORUM: MC_count dusmeli (eski vanilla LSTM'de Seed 23 direncliydi).\n")
cat("       BiLSTM'in geri-ileri yapisi direncligi kirarsa hoca'nin\n")
cat("       'MC yendik' iddiasi destek bulur.\n")

# --- 12. CSV ciktisi ---
out1 <- file.path(OUTDIR_SUM, "mcaware_BiLSTM_v1_RESULTS.csv")
out2 <- file.path(OUTDIR_SUM, "mcaware_BiLSTM_v1_SUMMARY.csv")
out3 <- file.path(OUTDIR_DIAG, "mcaware_BiLSTM_v1_SEED_REPORT.csv")
write.csv(df_res, out1, row.names = FALSE)
write.csv(summary_tbl, out2, row.names = FALSE)
write.csv(seed_mc, out3, row.names = FALSE)

cat("\nCSV'ler kaydedildi:\n")
cat("  ", out1, "\n")
cat("  ", out2, "\n")
cat("  ", out3, "\n")
cat("\nBu 3 CSV'yi Cowork'e geri yukle, sonuclari OTURUM_NOTLARI'na isleyecegim.\n")

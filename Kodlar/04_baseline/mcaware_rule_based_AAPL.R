# ===========================================================================
# MC-AWARE — NASDAQ AAPL KLASIK ML BASELINE (DENEY I.19)
# TUBITAK 2209-A — Yurutucu: Mehmet Ali KURT
# Olusturulma: 23 Mayis 2026 (v3 sonradan ek)
# ---------------------------------------------------------------------------
# AMACI:
#   "DL-ozgu anti-prediktif" iddiasini gelismis piyasa (NASDAQ) kontrolunde
#   guclendirmek. THYAO + GARAN'da klasik ML 0/4 + 1/4 sinirda. AAPL'da
#   klasik ML'nin de Naive seviyesinde kaldigi gosterilirse:
#     DL_THYAO = anti-prediktif (varlik-ozgu)
#     DL_GARAN/AAPL = rastgele (anti-prediktif degil)
#     ML_THYAO/GARAN/AAPL = Naive seviyesi (her yerde)
#   asimetrik gozlemi tamamlanir.
#
# MODELLER: Decision Tree (rpart), OneR, Random Forest, Logistic Regression
# CIKTI: Sonuclar/summaries/mcaware_rule_based_AAPL_RESULTS.csv
# Sure: ~5 dk
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- here::here()
OUTDIR  <- "here::here("Sonuclar")/summaries"
setwd(WORKDIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(quantmod)
  library(rpart)
})

# randomForest ve OneR opsiyonel
has_rf <- requireNamespace("randomForest", quietly = TRUE)
has_oner <- requireNamespace("OneR", quietly = TRUE)

cat("\n========================================================================\n")
cat("MC-AWARE — NASDAQ AAPL KLASIK ML BASELINE (I.19)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# --- Veri cek ---
TICKER <- "AAPL"
cat(sprintf("Veri cekiliyor: %s (2014-01-01 / 2026-03-31)...\n", TICKER))
getSymbols(TICKER, from = "2014-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
aapl <- get(TICKER)

# AAPL icin DXY, Oil, Fed_Rate cekmek istersek (BIST yerine):
getSymbols("DX-Y.NYB", from = "2014-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
dxy <- get("DX-Y.NYB")
getSymbols("CL=F", from = "2014-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
oil <- get("CL=F")

# Birlestir
df <- data.frame(
  Date  = as.character(index(aapl)),
  Open  = as.numeric(Op(aapl)),
  High  = as.numeric(Hi(aapl)),
  Low   = as.numeric(Lo(aapl)),
  Close = as.numeric(Cl(aapl)),
  Volume = as.numeric(Vo(aapl))
)
df <- df[df$Volume > 0 & complete.cases(df[, c("Open","High","Low","Close")]), ]

# DXY ve Oil ile hizala (LOCF)
dxy_df <- data.frame(Date = as.character(index(dxy)),
                     DXY = as.numeric(Cl(dxy)))
oil_df <- data.frame(Date = as.character(index(oil)),
                     Oil = as.numeric(Cl(oil)))
df <- df %>%
  left_join(dxy_df, by = "Date") %>%
  left_join(oil_df, by = "Date")
df$DXY <- zoo::na.locf(df$DXY, na.rm = FALSE)
df$Oil <- zoo::na.locf(df$Oil, na.rm = FALSE)

# Teknik gostergeler
df$RSI <- TTR::RSI(df$Close, n = 14)
macd_v <- TTR::MACD(df$Close); df$MACD <- macd_v[, "macd"]
df$EMA12 <- TTR::EMA(df$Close, n = 12)
df$EMA26 <- TTR::EMA(df$Close, n = 26)
stoch_v <- TTR::stoch(df[, c("High","Low","Close")])
df$SO_K <- stoch_v[, "fastK"]; df$SO_D <- stoch_v[, "fastD"]
adx_v <- TTR::ADX(df[, c("High","Low","Close")])
df$ADX <- adx_v[, "ADX"]
df <- df[28:nrow(df), ] %>% drop_na()
cat(sprintf("Temiz veri: %d satir\n", nrow(df)))

# --- Pencereleme (BIST scriptleriyle ayni) ---
IN_LEN <- 2L; OUT_LEN <- 1L  # gunluk yon
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","DXY","Oil")
F_DIM <- length(feat_cols)
feats <- as.matrix(df[, feat_cols])
prices <- df$Close; N <- nrow(feats)

X_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  X_list[[length(X_list) + 1L]] <- feats[(t - IN_LEN + 1L):t, , drop = FALSE]
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_arr <- array(unlist(X_list), dim = c(length(X_list), IN_LEN, F_DIM))
y_arr <- y_vec
n_total <- length(y_arr)

# Split (70/15/15)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_arr[1:i_tr, , , drop = FALSE]; y_tr <- y_arr[1:i_tr]
X_te <- X_arr[(i_va + OUT_LEN):n_total, , , drop = FALSE]
y_te <- y_arr[(i_va + OUT_LEN):n_total]

# Flatten for classical ML
X_tr_flat <- t(apply(X_tr, 1, c))
X_te_flat <- t(apply(X_te, 1, c))

naive_acc <- mean(y_te == as.integer(mean(y_tr) > 0.5))
cat(sprintf("Split: Tr=%d Te=%d | Up%%: Tr=%.1f Te=%.1f | Naive=%.3f\n",
            length(y_tr), length(y_te),
            100 * mean(y_tr), 100 * mean(y_te), naive_acc))

# --- Klasik ML modelleri ---
results <- list()

compute_eval <- function(name, pred) {
  pred_int <- as.integer(pred)
  acc <- mean(pred_int == y_te)
  flip_acc <- 1 - acc
  sens <- if (sum(y_te == 1) > 0) sum(pred_int == 1 & y_te == 1) / sum(y_te == 1) else NA
  spec <- if (sum(y_te == 0) > 0) sum(pred_int == 0 & y_te == 0) / sum(y_te == 0) else NA
  bal_acc <- mean(c(sens, spec), na.rm = TRUE)
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0) || is.na(spec) || is.na(sens)
  list(model = name, Acc = acc, Sens = sens, Spec = spec, BalAcc = bal_acc,
       Acc_flip = flip_acc, is_MC = is_mc,
       beats_naive = acc > naive_acc, flip_beats_naive = flip_acc > naive_acc)
}

# 1) Decision Tree
n0 <- sum(y_tr == 0); n1 <- sum(y_tr == 1)
p0 <- n1 / (n0 + n1); p1 <- 1 - p0  # ters orantili prior, dengeli
dt_model <- rpart(y ~ ., data = data.frame(y = factor(y_tr), X_tr_flat),
                  method = "class",
                  parms = list(prior = c(p0, p1)))
dt_pred <- predict(dt_model, data.frame(X_te_flat), type = "class")
results[[length(results) + 1]] <- compute_eval("DecisionTree",
                                                as.numeric(as.character(dt_pred)))

# 2) OneR (opsiyonel)
if (has_oner) {
  oner_df <- data.frame(y = factor(y_tr), X_tr_flat)
  oner_model <- OneR::OneR(oner_df, verbose = FALSE)
  oner_pred <- predict(oner_model, data.frame(X_te_flat))
  results[[length(results) + 1]] <- compute_eval("OneR",
                                                  as.numeric(as.character(oner_pred)))
} else {
  cat("OneR paketi yok, atlandi.\n")
}

# 3) Random Forest (opsiyonel)
if (has_rf) {
  rf_model <- randomForest::randomForest(x = X_tr_flat, y = factor(y_tr),
                                         ntree = 200, classwt = c(p0, p1))
  rf_pred <- predict(rf_model, X_te_flat)
  results[[length(results) + 1]] <- compute_eval("RandomForest",
                                                  as.numeric(as.character(rf_pred)))
} else {
  cat("randomForest paketi yok, atlandi.\n")
}

# 4) Logistic Regression
glm_df_tr <- data.frame(y = y_tr, X_tr_flat)
glm_model <- glm(y ~ ., data = glm_df_tr, family = binomial(),
                 weights = ifelse(y_tr == 1, p1, p0))
glm_prob <- predict(glm_model, data.frame(X_te_flat), type = "response")
glm_pred <- as.integer(glm_prob > 0.5)
results[[length(results) + 1]] <- compute_eval("LogisticRegression", glm_pred)

# --- Sonuclari kaydet ---
res_df <- do.call(rbind, lapply(results, as.data.frame))
print(res_df)

if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE)
out_file <- file.path(OUTDIR, "mcaware_rule_based_AAPL_RESULTS.csv")
write.csv(res_df, out_file, row.names = FALSE)
cat(sprintf("\nKaydedildi: %s\n", out_file))

cat("\n========================================================================\n")
cat("OZET — AAPL Klasik ML\n")
cat("========================================================================\n")
cat(sprintf("Naive: %.3f\n", naive_acc))
cat(sprintf("beats_naive sayisi: %d/%d\n",
            sum(res_df$beats_naive), nrow(res_df)))
cat(sprintf("flip_beats_naive sayisi: %d/%d\n",
            sum(res_df$flip_beats_naive), nrow(res_df)))
cat("\nBEKLEME: 0/4 beats_naive + 0/4 flip_beats_naive → DL anti-pred BIST'e ozgu\n")
cat("AAPL KLASIK ML BASELINE TAMAMLANDI.\n")

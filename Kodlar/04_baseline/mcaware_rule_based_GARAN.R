# ===========================================================================
# MC-AWARE — RULE-BASED CLASSIFIER BASELINE (ADIM I.17, GARAN DOGRULAMA)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   Klasik rule-based siniflandiricilarin (DT, RIPPER, OneR) GARAN yön
#   tahmininde nasil performans verdigini test et. "DL anti-prediktif,
#   acaba klasik ML de oyle mi yoksa bu DL'e ozgu mu?" sorusunu kapatir.
#
# NEDEN ANLAMLI:
#   1. PDF'teki "Majority Rules baseline" maddesinin somut karsiligi
#   2. Rule-based modeller "tek karar agaci" gibi yorumlanabilir → XAI
#   3. Eger rule-based de anti-prediktif → mekanizma VERIDE
#      Eger rule-based Naive'i geciyor → DL'in mimari yetersizligi var
#
# YONTEM:
#   1. v3b ile AYNI feature seti (13 feat) ve AYNI split (70/15/15)
#   2. Üç klasik model:
#      (a) Decision Tree (rpart) — yorumlanabilir, karar agaci
#      (b) C5.0 Rules (C50)     — RIPPER benzeri kural ureticisi
#      (c) OneR                  — tek-feature kural
#   3. Random Forest (randomForest) — ensemble karsilastirmasi
#   4. Logistic Regression       — lineer baseline
#
# NEDEN PENCERELI DEGIL:
#   Rule-based modeller "zaman dizisi" anlamaz, sample bazli sinif yapar.
#   Bu yuzden t-1 ve t-2 günleri ayri feature olarak duzlestirilir
#   (flatten): F_DIM_flat = 2 * 13 = 26 feature.
#
# CIKTI: 1 SUMMARY CSV + her model icin PREDICTIONS CSV
# Calistirma: RStudio → Ctrl+Shift+S → ~5-10 dk → CSV'ler
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


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

# Yardimci: paket yoksa otomatik kurmayi dene, basaramazsa FALSE dondur
ensure_pkg <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) return(TRUE)
  cat(sprintf("UYARI: '%s' paketi yok. Kurulum deneniyor...\n", pkg))
  ok <- tryCatch({
    utils::install.packages(pkg, repos = "https://cloud.r-project.org",
                            quiet = TRUE)
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) {
    cat(sprintf("  Kurulum basarisiz: %s\n", e$message)); FALSE
  }, warning = function(w) {
    requireNamespace(pkg, quietly = TRUE)
  })
  if (!ok) cat(sprintf("  '%s' yok sayilacak (model atlanir).\n", pkg))
  ok
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(TTR)
  library(zoo)
  library(quantmod)
  library(rpart)          # Decision Tree (zorunlu)
})

# Opsiyonel paketler — yoksa ilgili model atlanir, script duser DEGIL
have_rf   <- ensure_pkg("randomForest")  # Random Forest
have_c50  <- ensure_pkg("C50")           # C5.0 Rules (RIPPER benzeri)
have_oner <- ensure_pkg("OneR")          # OneR (tek-feature kural)

if (have_rf)   suppressPackageStartupMessages(library(randomForest))

cat("\n========================================================================\n")
cat("MC-AWARE — RULE-BASED BASELINE (ADIM I.17 GARAN)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Modeller: rpart, C5.0 Rules, OneR, randomForest, glm\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

# --- 1. Veri (v3b ile AYNI) ---
cat("GARAN verisi cekiliyor...\n")
getSymbols("GARAN.IS", from = "2018-01-01", to = "2026-03-31",
           auto.assign = TRUE, warnings = FALSE)
garan_xts <- GARAN.IS
garan_df <- data.frame(
  Date   = as.character(index(garan_xts)),
  Open   = as.numeric(Op(garan_xts)),
  High   = as.numeric(Hi(garan_xts)),
  Low    = as.numeric(Lo(garan_xts)),
  Close  = as.numeric(Cl(garan_xts)),
  Volume = as.numeric(Vo(garan_xts))
)
garan_df <- garan_df[garan_df$Volume > 0, ]
garan_df <- garan_df[complete.cases(garan_df[, c("Open","High","Low","Close")]), ]

# Indikatorler
garan_df$RSI   <- TTR::RSI(garan_df$Close, n = 14)
mac <- TTR::MACD(garan_df$Close); garan_df$MACD <- mac[,"macd"]
garan_df$EMA12 <- TTR::EMA(garan_df$Close, n = 12)
garan_df$EMA26 <- TTR::EMA(garan_df$Close, n = 26)
st <- TTR::stoch(garan_df[,c("High","Low","Close")])
garan_df$SO_K <- st[,"fastK"]; garan_df$SO_D <- st[,"fastD"]
garan_df$ADX  <- TTR::ADX(garan_df[,c("High","Low","Close")])[,"ADX"]

# Dis degiskenler
tryCatch({
  getSymbols("USDTRY=X", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  usdtry_df <- data.frame(Date = as.character(index(`USDTRY=X`)),
                          USDTRY = as.numeric(Cl(`USDTRY=X`)))
}, error = function(e) usdtry_df <<- data.frame(Date=character(0), USDTRY=numeric(0)))

tryCatch({
  getSymbols("CL=F", from = "2018-01-01", to = "2026-03-31",
             auto.assign = TRUE, warnings = FALSE)
  oil_df <- data.frame(Date = as.character(index(`CL=F`)),
                       Oil = as.numeric(Cl(`CL=F`)))
}, error = function(e) oil_df <<- data.frame(Date=character(0), Oil=numeric(0)))

tryCatch({
  getSymbols("INTDSRTRM193N", src = "FRED", from = "2018-01-01",
             to = "2026-03-31", auto.assign = TRUE, warnings = FALSE)
  tcmb_df <- data.frame(Date = as.Date(index(INTDSRTRM193N)),
                        TCMB_Rate = as.numeric(INTDSRTRM193N))
  tcmb_daily <- data.frame(Date = as.Date(garan_df$Date)) %>%
    mutate(YearMonth = format(Date, "%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth = format(Date, "%Y-%m")),
              by = "YearMonth") %>%
    select(Date = Date.x, TCMB_Rate)
}, error = function(e) tcmb_daily <<- data.frame(Date=as.Date(garan_df$Date),
                                                  TCMB_Rate=NA_real_))

garan_final <- garan_df %>%
  left_join(usdtry_df, by = "Date") %>%
  left_join(oil_df, by = "Date") %>%
  left_join(tcmb_daily %>% mutate(Date = as.character(Date)), by = "Date")
garan_final$USDTRY    <- zoo::na.locf(garan_final$USDTRY, na.rm = FALSE)
garan_final$Oil       <- zoo::na.locf(garan_final$Oil, na.rm = FALSE)
garan_final$TCMB_Rate <- zoo::na.locf(garan_final$TCMB_Rate, na.rm = FALSE)
garan_final <- garan_final[28:nrow(garan_final), ] %>% drop_na()
cat(sprintf("Final GARAN: %d satir\n", nrow(garan_final)))

# --- 2. Etiket ve flatten (zaman dizisi YOK, t-1 ve t ayri kolon) ---
IN_LEN <- 2L; OUT_LEN <- 3L
feat_cols <- c("Close","Open","Volume","RSI","MACD","EMA12","EMA26",
               "SO_K","SO_D","ADX","USDTRY","Oil","TCMB_Rate")
F_DIM <- length(feat_cols)
feats  <- as.matrix(garan_final[, feat_cols])
prices <- garan_final$Close
N <- nrow(feats)

# Flatten: her sample icin t-1 ve t feature'lari yan-yana
X_flat_list <- list(); y_vec <- c()
for (t in (IN_LEN + 1):(N - OUT_LEN)) {
  row_t1 <- feats[t - 1L, ]
  row_t  <- feats[t, ]
  flat <- c(setNames(row_t1, paste0(feat_cols, "_lag1")),
            setNames(row_t,  paste0(feat_cols, "_lag0")))
  X_flat_list[[length(X_flat_list) + 1L]] <- flat
  y_vec <- c(y_vec, as.integer(prices[t + OUT_LEN] > prices[t]))
}
X_flat <- do.call(rbind, X_flat_list)
y_vec  <- factor(y_vec, levels = c(0, 1), labels = c("Down", "Up"))

cat(sprintf("Flat feature matrisi: %d sample x %d feature\n",
            nrow(X_flat), ncol(X_flat)))

# --- 3. Split (v3b ile AYNI: 70/15/15) ---
n_total <- length(y_vec)
i_tr <- floor(n_total * 0.70); i_va <- floor(n_total * 0.85)
X_tr <- X_flat[1:i_tr, ]; y_tr <- y_vec[1:i_tr]
X_va <- X_flat[(i_tr+1):i_va, ]; y_va <- y_vec[(i_tr+1):i_va]
X_te <- X_flat[(i_va+1):n_total, ]; y_te <- y_vec[(i_va+1):n_total]

# Train+val birlestir (rule-based modeller validation set kullanmaz)
X_trva <- rbind(X_tr, X_va)
y_trva <- c(y_tr, y_va)

cat(sprintf("Split: Train+Val=%d | Test=%d\n", nrow(X_trva), nrow(X_te)))

# Normalizasyon - rule-based gerektirmez ama RF ve glm icin tutarli olsun
mu <- apply(X_trva, 2, mean); sd_ <- apply(X_trva, 2, stats::sd) + 1e-8
X_trva_n <- scale(X_trva, center = mu, scale = sd_)
X_te_n   <- scale(X_te,   center = mu, scale = sd_)

# Data.frame'e cevir
df_trva <- data.frame(X_trva, y = y_trva)
df_te   <- data.frame(X_te,   y = y_te)
df_trva_n <- data.frame(X_trva_n, y = y_trva)
df_te_n   <- data.frame(X_te_n,   y = y_te)

# Naive baseline
naive_class <- names(sort(table(y_trva), decreasing = TRUE))[1]
naive_acc <- mean(y_te == naive_class)
cat(sprintf("Naive baseline (majority='%s'): Acc = %.4f\n", naive_class, naive_acc))

# --- 4. Metric helper ---
compute_metrics <- function(y_true, y_pred) {
  y_pred <- factor(y_pred, levels = c("Down", "Up"))
  y_true <- factor(y_true, levels = c("Down", "Up"))
  tp <- sum(y_pred == "Up" & y_true == "Up")
  tn <- sum(y_pred == "Down" & y_true == "Down")
  fp <- sum(y_pred == "Up" & y_true == "Down")
  fn <- sum(y_pred == "Down" & y_true == "Up")
  n <- length(y_true)
  acc <- (tp + tn) / n
  sens <- if ((tp+fn) > 0) tp/(tp+fn) else NA_real_
  spec <- if ((tn+fp) > 0) tn/(tn+fp) else NA_real_
  bacc <- if (!is.na(sens) && !is.na(spec)) (sens + spec) / 2 else NA_real_
  is_mc <- isTRUE(spec == 0) || isTRUE(sens == 0)
  list(Acc = acc, Sens = sens, Spec = spec, BalAcc = bacc,
       is_MC = is_mc, Acc_flip = 1 - acc)
}

# --- 5. Modelleri egit ve test et ---
results <- list()

# (a) Decision Tree (rpart)
cat("\n[1/5] Decision Tree (rpart)...\n")
fit_dt <- rpart(y ~ ., data = df_trva, method = "class",
                control = rpart.control(cp = 0.01, minsplit = 20))
pred_dt <- predict(fit_dt, df_te, type = "class")
m_dt <- compute_metrics(y_te, pred_dt)
results[["DecisionTree"]] <- m_dt
cat(sprintf("  Acc=%.3f  Spec=%.3f  Sens=%.3f  MC=%s  Flip=%.3f\n",
            m_dt$Acc, m_dt$Spec, m_dt$Sens, m_dt$is_MC, m_dt$Acc_flip))

# (b) C5.0 Rules (RIPPER benzeri)
if (have_c50) {
  cat("\n[2/5] C5.0 Rules (RIPPER benzeri)...\n")
  fit_c50 <- C50::C5.0(x = df_trva[, -ncol(df_trva)], y = df_trva$y,
                        rules = TRUE)
  pred_c50 <- predict(fit_c50, df_te[, -ncol(df_te)])
  m_c50 <- compute_metrics(y_te, pred_c50)
  results[["C50_Rules"]] <- m_c50
  cat(sprintf("  Acc=%.3f  Spec=%.3f  Sens=%.3f  MC=%s  Flip=%.3f\n",
              m_c50$Acc, m_c50$Spec, m_c50$Sens, m_c50$is_MC, m_c50$Acc_flip))
  cat("  KURALLAR:\n")
  print(summary(fit_c50))
} else {
  cat("\n[2/5] C5.0 ATLANDI (paket yok)\n")
}

# (c) OneR
if (have_oner) {
  cat("\n[3/5] OneR (tek-feature kural)...\n")
  fit_oner <- OneR::OneR(y ~ ., data = df_trva, verbose = FALSE)
  pred_oner <- predict(fit_oner, df_te)
  m_oner <- compute_metrics(y_te, pred_oner)
  results[["OneR"]] <- m_oner
  cat(sprintf("  Acc=%.3f  Spec=%.3f  Sens=%.3f  MC=%s  Flip=%.3f\n",
              m_oner$Acc, m_oner$Spec, m_oner$Sens, m_oner$is_MC, m_oner$Acc_flip))
  cat("  KURAL:\n"); print(fit_oner)
} else {
  cat("\n[3/5] OneR ATLANDI (paket yok)\n")
}

# (d) Random Forest
if (have_rf) {
  cat("\n[4/5] Random Forest...\n")
  set.seed(42)
  fit_rf <- randomForest::randomForest(y ~ ., data = df_trva_n, ntree = 500)
  pred_rf <- predict(fit_rf, df_te_n)
  m_rf <- compute_metrics(y_te, pred_rf)
  results[["RandomForest"]] <- m_rf
  cat(sprintf("  Acc=%.3f  Spec=%.3f  Sens=%.3f  MC=%s  Flip=%.3f\n",
              m_rf$Acc, m_rf$Spec, m_rf$Sens, m_rf$is_MC, m_rf$Acc_flip))
} else {
  cat("\n[4/5] Random Forest ATLANDI (paket yok)\n")
}

# (e) Logistic Regression
cat("\n[5/5] Logistic Regression...\n")
fit_glm <- glm(y ~ ., data = df_trva_n, family = binomial())
pred_glm_prob <- predict(fit_glm, df_te_n, type = "response")
pred_glm <- factor(ifelse(pred_glm_prob > 0.5, "Up", "Down"),
                   levels = c("Down","Up"))
m_glm <- compute_metrics(y_te, pred_glm)
results[["LogisticRegression"]] <- m_glm
cat(sprintf("  Acc=%.3f  Spec=%.3f  Sens=%.3f  MC=%s  Flip=%.3f\n",
            m_glm$Acc, m_glm$Spec, m_glm$Sens, m_glm$is_MC, m_glm$Acc_flip))

# --- 6. Sonuc tablosu ---
results_df <- data.frame(
  model = names(results),
  Acc      = sapply(results, function(r) r$Acc),
  Sens     = sapply(results, function(r) r$Sens),
  Spec     = sapply(results, function(r) r$Spec),
  BalAcc   = sapply(results, function(r) r$BalAcc),
  Acc_flip = sapply(results, function(r) r$Acc_flip),
  is_MC    = sapply(results, function(r) r$is_MC),
  beats_naive      = sapply(results, function(r) r$Acc > naive_acc),
  flip_beats_naive = sapply(results, function(r) r$Acc_flip > naive_acc),
  stringsAsFactors = FALSE
)

cat("\n", strrep("=", 80), "\n", sep = "")
cat("RULE-BASED BASELINE SONUCLARI (test seti)\n")
cat(strrep("=", 80), "\n", sep = "")
cat(sprintf("Naive baseline: %.4f\n\n", naive_acc))
print(results_df, row.names = FALSE)

cat("\n", strrep("=", 80), "\n", sep = "")
cat("KARAR MATRISI\n")
cat(strrep("=", 80), "\n", sep = "")

n_beats_naive <- sum(results_df$beats_naive)
n_flip_beats  <- sum(results_df$flip_beats_naive)
n_mc          <- sum(results_df$is_MC)
n_models      <- nrow(results_df)

if (n_beats_naive >= n_models / 2) {
  cat("[A] KLASIK ML NAIVE'I GECTI:\n")
  cat(sprintf("    %d/%d model Naive'i geciyor.\n", n_beats_naive, n_models))
  cat("    Rule-based modeller anti-prediktif DEGIL → mekanizma DL'e ozgu.\n")
  cat("    Bu BUYUK BIR BULGU: DL anti-prediktivitesi mimari yetersizligi.\n")
} else if (n_flip_beats >= n_models / 2) {
  cat("[B] KLASIK ML DE ANTI-PREDIKTIF:\n")
  cat(sprintf("    %d/%d model flip Naive'i geciyor.\n", n_flip_beats, n_models))
  cat("    Hem DL hem klasik ML anti-prediktif → mekanizma VERIDE.\n")
  cat("    Yorum 3'u COK GUCLENDIRIR: 'sadece DL degil, klasik ML de\n")
  cat("    BIST'in makro degisken korelasyon kirilmasindan etkileniyor.'\n")
} else {
  cat("[C] KARISIK:\n")
  cat(sprintf("    %d beats_naive, %d flip_beats, %d MC\n",
              n_beats_naive, n_flip_beats, n_mc))
  cat("    Heterojen sonuc. Manuel inceleme gerek.\n")
}

# --- 7. CSV cikti ---
out <- file.path(OUTDIR_SUM, "mcaware_rule_based_GARAN_RESULTS.csv")
write.csv(results_df, out, row.names = FALSE)
cat(sprintf("\nCSV kaydedildi: %s\n", out))
cat("\nCSV'yi yukleyince Claude Bolum 10.39 (ADIM I.17 GARAN dogrulamasi) olarak isleyecek.\n")

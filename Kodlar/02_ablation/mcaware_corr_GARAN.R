# ===========================================================================
# MC-AWARE — GARAN KORELASYON KIRILMASI ANALİZİ (ADIM I.18)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   Y5 hipotezini sayısal kanıtla desteklemek:
#   "THYAO'da korelasyon kırılması BÜYÜK → anti-prediktif davranış var.
#    GARAN'da korelasyon kırılması KÜÇÜK mü? → anti-prediktif yok."
#
#   THYAO korelasyonları zaten mcaware_corr_analysis.csv'de mevcut.
#   Bu script GARAN için AYNI analizi yapıp karşılaştırma tablosu üretir.
#
# DÜRÜSTLÜK NOTU:
#   Eğer GARAN kırılması da BÜYÜK çıkarsa → "korelasyon kırılması =
#   anti-prediktif" açıklaması daha da ZAYIFLAR (AAPL gibi).
#   Bu sonuç da dürüstçe raporlanacaktır.
#
# ÇIKTI:
#   mcaware_corr_GARAN.csv         — GARAN korelasyonları
#   mcaware_corr_COMPARISON.csv    — THYAO vs GARAN vs AAPL karşılaştırma
# Süre: ~2-3 dk (model eğitimi YOK, sadece korelasyon hesabı)
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

suppressPackageStartupMessages({
  library(tidyverse); library(zoo); library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE — GARAN KORELASYON KIRILMASI ANALİZİ (ADIM I.18)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

# ═══ GARAN VERİSİ ═══
cat("GARAN verisi çekiliyor...\n")
tryCatch({
  getSymbols("GARAN.IS", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  garan_xts <- GARAN.IS
  garan_df <- data.frame(
    Date=as.character(index(garan_xts)),
    Open=as.numeric(Op(garan_xts)), High=as.numeric(Hi(garan_xts)),
    Low=as.numeric(Lo(garan_xts)), Close=as.numeric(Cl(garan_xts)),
    Volume=as.numeric(Vo(garan_xts)))
  garan_df <- garan_df[garan_df$Volume > 0 & complete.cases(garan_df[,c("Open","High","Low","Close")]), ]
  cat(sprintf("  GARAN ham veri: %d satır\n", nrow(garan_df)))
}, error=function(e) {
  stop(paste("GARAN verisi çekilemedi:", conditionMessage(e)))
})

# ═══ MAKRO DEĞİŞKENLER ═══
cat("Makro değişkenler çekiliyor...\n")

# USDTRY
tryCatch({
  getSymbols("USDTRY=X", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  usdtry_df <- data.frame(Date=as.character(index(`USDTRY=X`)), USDTRY=as.numeric(Cl(`USDTRY=X`)))
  cat(sprintf("  USDTRY: %d satır\n", nrow(usdtry_df)))
}, error=function(e) {
  cat("  USDTRY çekilemedi:", conditionMessage(e), "\n")
  usdtry_df <<- data.frame(Date=character(0), USDTRY=numeric(0))
})

# Oil (WTI)
tryCatch({
  getSymbols("CL=F", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  oil_df <- data.frame(Date=as.character(index(`CL=F`)), Oil=as.numeric(Cl(`CL=F`)))
  cat(sprintf("  Oil: %d satır\n", nrow(oil_df)))
}, error=function(e) {
  cat("  Oil çekilemedi:", conditionMessage(e), "\n")
  oil_df <<- data.frame(Date=character(0), Oil=numeric(0))
})

# TCMB Rate (FRED)
tryCatch({
  getSymbols("INTDSRTRM193N", src="FRED", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  tcmb_df <- data.frame(Date=as.Date(index(INTDSRTRM193N)), TCMB_Rate=as.numeric(INTDSRTRM193N))
  tcmb_daily <- data.frame(Date=as.Date(garan_df$Date)) %>%
    mutate(YearMonth=format(Date,"%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth=format(Date,"%Y-%m")), by="YearMonth") %>%
    select(Date=Date.x, TCMB_Rate)
  cat(sprintf("  TCMB Rate: %d aylık → günlüğe dönüştürüldü\n", nrow(tcmb_df)))
}, error=function(e) {
  cat("  TCMB Rate çekilemedi:", conditionMessage(e), "\n")
  tcmb_daily <<- data.frame(Date=as.Date(garan_df$Date), TCMB_Rate=NA_real_)
})

# ═══ VERİ BİRLEŞTİRME ═══
garan_final <- garan_df %>%
  left_join(usdtry_df, by="Date") %>% left_join(oil_df, by="Date") %>%
  left_join(tcmb_daily %>% mutate(Date=as.character(Date)), by="Date")
garan_final$USDTRY <- zoo::na.locf(garan_final$USDTRY, na.rm=FALSE)
garan_final$Oil <- zoo::na.locf(garan_final$Oil, na.rm=FALSE)
garan_final$TCMB_Rate <- zoo::na.locf(garan_final$TCMB_Rate, na.rm=FALSE)
garan_final <- garan_final %>% drop_na()
N <- nrow(garan_final)
cat(sprintf("\nGARAN final veri: %d satır\n", N))

# ═══ BÖLÜM A: GARAN KORELASYON KIRILMASI ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BÖLÜM A: GARAN — TRAIN vs TEST KORELASYON ANALİZİ\n")
cat(strrep("=", 80), "\n", sep="")

i_split <- floor(N * 0.70)
train_data <- garan_final[1:i_split, ]
test_data  <- garan_final[(i_split+1):N, ]

cat(sprintf("  Train: %d satır (%s → %s)\n", nrow(train_data),
            train_data$Date[1], tail(train_data$Date,1)))
cat(sprintf("  Test:  %d satır (%s → %s)\n", nrow(test_data),
            test_data$Date[1], tail(test_data$Date,1)))

macro_vars <- c("USDTRY", "Oil", "TCMB_Rate")
target_var <- "Close"

corr_rows <- list()
for (mv in macro_vars) {
  cor_train <- cor(train_data[[target_var]], train_data[[mv]], use="complete.obs")
  cor_test  <- cor(test_data[[target_var]], test_data[[mv]], use="complete.obs")
  cor_diff  <- cor_test - cor_train

  # Log-return korelasyonu
  tr_ret <- diff(log(train_data[[target_var]])); tr_mv_ret <- diff(log(train_data[[mv]]))
  te_ret <- diff(log(test_data[[target_var]])); te_mv_ret <- diff(log(test_data[[mv]]))
  cor_train_ret <- cor(tr_ret, tr_mv_ret, use="complete.obs")
  cor_test_ret  <- cor(te_ret, te_mv_ret, use="complete.obs")

  cat(sprintf("\n  %s:\n", mv))
  cat(sprintf("    Fiyat korelasyonu:  Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train, cor_test, cor_diff))
  cat(sprintf("    Return korelasyonu: Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train_ret, cor_test_ret, cor_test_ret - cor_train_ret))

  corr_rows[[length(corr_rows)+1]] <- data.frame(
    market="BIST_GARAN", variable=mv, metric="price_level",
    cor_train=cor_train, cor_test=cor_test, cor_diff=cor_diff,
    stringsAsFactors=FALSE)
  corr_rows[[length(corr_rows)+1]] <- data.frame(
    market="BIST_GARAN", variable=mv, metric="log_return",
    cor_train=cor_train_ret, cor_test=cor_test_ret, cor_diff=cor_test_ret-cor_train_ret,
    stringsAsFactors=FALSE)
}

garan_corr_df <- do.call(rbind, corr_rows)
write.csv(garan_corr_df, file.path(OUTDIR_DIAG, "mcaware_corr_GARAN.csv"), row.names=FALSE)
cat("\n\nGARAN korelasyon CSV kaydedildi.\n")

# ═══ BÖLÜM B: THYAO vs GARAN vs AAPL KARŞILAŞTIRMA ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BÖLÜM B: ÜÇ VARLIK KORELASYON KIRILMASI KARŞILAŞTIRMASI\n")
cat(strrep("=", 80), "\n", sep="")

# Mevcut THYAO ve AAPL sonuçlarını oku
thyao_corr_file <- file.path(OUTDIR_DIAG, "mcaware_corr_analysis.csv")
nasdaq_corr_file <- file.path(OUTDIR_DIAG, "mcaware_nasdaq_CORR.csv")

comparison_rows <- list()

# GARAN sonuçları (az önce hesapladık)
for (i in 1:nrow(garan_corr_df)) {
  if (garan_corr_df$metric[i] == "price_level") {
    comparison_rows[[length(comparison_rows)+1]] <- data.frame(
      market="BIST_GARAN",
      variable=garan_corr_df$variable[i],
      cor_train=garan_corr_df$cor_train[i],
      cor_test=garan_corr_df$cor_test[i],
      cor_diff=garan_corr_df$cor_diff[i],
      abs_diff=abs(garan_corr_df$cor_diff[i]),
      anti_prediktif="HAYIR (7/15, rastgele)",
      stringsAsFactors=FALSE)
  }
}

# THYAO sonuçları (mevcut CSV'den)
if (file.exists(thyao_corr_file)) {
  thyao_corr <- read.csv(thyao_corr_file)
  thyao_price <- thyao_corr[thyao_corr$metric == "price_level", ]
  for (i in 1:nrow(thyao_price)) {
    comparison_rows[[length(comparison_rows)+1]] <- data.frame(
      market="BIST_THYAO",
      variable=thyao_price$variable[i],
      cor_train=thyao_price$cor_train[i],
      cor_test=thyao_price$cor_test[i],
      cor_diff=thyao_price$cor_diff[i],
      abs_diff=abs(thyao_price$cor_diff[i]),
      anti_prediktif="EVET (118/120, p<10^-15)",
      stringsAsFactors=FALSE)
  }
}

# AAPL sonuçları (mevcut CSV'den)
if (file.exists(nasdaq_corr_file)) {
  nasdaq_corr <- read.csv(nasdaq_corr_file)
  aapl_rows <- nasdaq_corr[nasdaq_corr$market == "NASDAQ_AAPL", ]
  for (i in 1:nrow(aapl_rows)) {
    comparison_rows[[length(comparison_rows)+1]] <- data.frame(
      market="NASDAQ_AAPL",
      variable=aapl_rows$variable[i],
      cor_train=aapl_rows$cor_train[i],
      cor_test=aapl_rows$cor_test[i],
      cor_diff=aapl_rows$cor_diff[i],
      abs_diff=abs(aapl_rows$cor_diff[i]),
      anti_prediktif="HAYIR (0/6)",
      stringsAsFactors=FALSE)
  }
}

comparison_df <- do.call(rbind, comparison_rows)
write.csv(comparison_df, file.path(OUTDIR_DIAG, "mcaware_corr_COMPARISON.csv"), row.names=FALSE)

# ═══ SONUÇ TABLOSU ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.18 — KORELASYON KIRILMASI KARŞILAŞTIRMA TABLOSU\n")
cat(strrep("=", 80), "\n", sep="")

cat("\n  Varlık + Değişken        Cor_Train  Cor_Test   FARK     |FARK|  Anti-pred?\n")
cat("  ", strrep("-", 80), "\n", sep="")
for (i in 1:nrow(comparison_df)) {
  r <- comparison_df[i,]
  label <- sprintf("%-12s %-10s", r$market, r$variable)
  cat(sprintf("  %-25s  %+.3f     %+.3f    %+.3f   %.3f   %s\n",
              label, r$cor_train, r$cor_test, r$cor_diff, r$abs_diff,
              r$anti_prediktif))
}

# ═══ DÜRÜST YORUM ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.18 — DÜRÜST YORUM\n")
cat(strrep("=", 80), "\n", sep="")

# GARAN kırılma büyüklüğü ortalaması
garan_price <- garan_corr_df[garan_corr_df$metric == "price_level", ]
garan_mean_abs_diff <- mean(abs(garan_price$cor_diff))

cat(sprintf("\n  GARAN ortalama |kırılma|: %.3f\n", garan_mean_abs_diff))

# THYAO kırılma büyüklüğü
if (exists("thyao_price")) {
  thyao_mean_abs_diff <- mean(thyao_price$abs_diff)
} else {
  thyao_mean_abs_diff <- mean(c(0.496, 0.562, 0.117))
}
cat(sprintf("  THYAO ortalama |kırılma|: %.3f (önceki I.12'den)\n", thyao_mean_abs_diff))

# AAPL kırılma büyüklüğü
if (exists("aapl_rows")) {
  aapl_mean_abs_diff <- mean(aapl_rows$abs_diff)
} else {
  aapl_mean_abs_diff <- mean(c(0.760, 1.056, 0.935))
}
cat(sprintf("  AAPL  ortalama |kırılma|: %.3f (önceki I.13'den)\n", aapl_mean_abs_diff))

cat("\n  KARAR MATRİSİ:\n")
if (garan_mean_abs_diff < thyao_mean_abs_diff * 0.7) {
  cat("  [A] GARAN kırılması THYAO'dan KÜÇÜK → Y5 DESTEKLENİYOR\n")
  cat("      Makro-hassas varlıklarda büyük kırılma + anti-prediktif\n")
  cat("      Dağıtık hassas varlıklarda küçük kırılma + anti-prediktif yok\n")
} else if (garan_mean_abs_diff >= thyao_mean_abs_diff * 0.7 &&
           garan_mean_abs_diff <= thyao_mean_abs_diff * 1.3) {
  cat("  [B] GARAN kırılması THYAO ile BENZERİ → Y5 ZAYIFLIYOR\n")
  cat("      Benzer kırılma ama farklı davranış = kırılma TEK BAŞINA\n")
  cat("      yeterli değil. AAPL çelişkisine ek bir çelişki.\n")
  cat("      DÜRÜST RAPORLAMA: Bu sonuç Y5'i desteklemiyor.\n")
} else {
  cat("  [C] GARAN kırılması THYAO'dan BÜYÜK → Y5 ÇÜRÜTÜLDÜ\n")
  cat("      AAPL gibi büyük kırılma ama anti-prediktif yok.\n")
  cat("      DÜRÜST RAPORLAMA: Korelasyon kırılması açıklaması yetersiz.\n")
}

cat(sprintf("\n  NOT: AAPL'da kırılma EN BÜYÜK (ortalama %.3f) ama anti-prediktif\n", aapl_mean_abs_diff))
cat("  YOK. Bu, korelasyon kırılmasının GEREKLI ama YETERLİ OLMAYAN\n")
cat("  bir koşul olduğuna işaret eder. Ek faktörler (piyasa etkinliği,\n")
cat("  likidite, trader profili) rol oynuyor olabilir.\n")

 # ===========================================================================
# MC-AWARE — GARAN KORELASYON KIRILMASI ANALİZİ (ADIM I.18)
# TÜBİTAK 2209-A — Yürütücü: Mehmet Ali KURT
# Tarih: 23.05.2026
# ---------------------------------------------------------------------------
# AMACI:
#   Y5 hipotezini sayısal kanıtla desteklemek:
#   "THYAO'da korelasyon kırılması BÜYÜK → anti-prediktif davranış var.
#    GARAN'da korelasyon kırılması KÜÇÜK mü? → anti-prediktif yok."
#
#   THYAO korelasyonları zaten mcaware_corr_analysis.csv'de mevcut.
#   Bu script GARAN için AYNI analizi yapıp karşılaştırma tablosu üretir.
#
# DÜRÜSTLÜK NOTU:
#   Eğer GARAN kırılması da BÜYÜK çıkarsa → "korelasyon kırılması =
#   anti-prediktif" açıklaması daha da ZAYIFLAR (AAPL gibi).
#   Bu sonuç da dürüstçe raporlanacaktır.
#
# ÇIKTI:
#   mcaware_corr_GARAN.csv         — GARAN korelasyonları
#   mcaware_corr_COMPARISON.csv    — THYAO vs GARAN vs AAPL karşılaştırma
# Süre: ~2-3 dk (model eğitimi YOK, sadece korelasyon hesabı)
# ===========================================================================
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


WORKDIR <- here::here()
setwd(WORKDIR)

suppressPackageStartupMessages({
  library(tidyverse); library(zoo); library(quantmod)
})

cat("\n========================================================================\n")
cat("MC-AWARE — GARAN KORELASYON KIRILMASI ANALİZİ (ADIM I.18)\n")
cat("Tarih:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("========================================================================\n\n")

# [B18] if (!dir.exists(OUTDIR)) { OUTDIR <- WORKDIR }

# ═══ GARAN VERİSİ ═══
cat("GARAN verisi çekiliyor...\n")
tryCatch({
  getSymbols("GARAN.IS", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  garan_xts <- GARAN.IS
  garan_df <- data.frame(
    Date=as.character(index(garan_xts)),
    Open=as.numeric(Op(garan_xts)), High=as.numeric(Hi(garan_xts)),
    Low=as.numeric(Lo(garan_xts)), Close=as.numeric(Cl(garan_xts)),
    Volume=as.numeric(Vo(garan_xts)))
  garan_df <- garan_df[garan_df$Volume > 0 & complete.cases(garan_df[,c("Open","High","Low","Close")]), ]
  cat(sprintf("  GARAN ham veri: %d satır\n", nrow(garan_df)))
}, error=function(e) {
  stop(paste("GARAN verisi çekilemedi:", conditionMessage(e)))
})

# ═══ MAKRO DEĞİŞKENLER ═══
cat("Makro değişkenler çekiliyor...\n")

# USDTRY
tryCatch({
  getSymbols("USDTRY=X", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  usdtry_df <- data.frame(Date=as.character(index(`USDTRY=X`)), USDTRY=as.numeric(Cl(`USDTRY=X`)))
  cat(sprintf("  USDTRY: %d satır\n", nrow(usdtry_df)))
}, error=function(e) {
  cat("  USDTRY çekilemedi:", conditionMessage(e), "\n")
  usdtry_df <<- data.frame(Date=character(0), USDTRY=numeric(0))
})

# Oil (WTI)
tryCatch({
  getSymbols("CL=F", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  oil_df <- data.frame(Date=as.character(index(`CL=F`)), Oil=as.numeric(Cl(`CL=F`)))
  cat(sprintf("  Oil: %d satır\n", nrow(oil_df)))
}, error=function(e) {
  cat("  Oil çekilemedi:", conditionMessage(e), "\n")
  oil_df <<- data.frame(Date=character(0), Oil=numeric(0))
})

# TCMB Rate (FRED)
tryCatch({
  getSymbols("INTDSRTRM193N", src="FRED", from="2018-01-01", to="2026-03-31", auto.assign=TRUE, warnings=FALSE)
  tcmb_df <- data.frame(Date=as.Date(index(INTDSRTRM193N)), TCMB_Rate=as.numeric(INTDSRTRM193N))
  tcmb_daily <- data.frame(Date=as.Date(garan_df$Date)) %>%
    mutate(YearMonth=format(Date,"%Y-%m")) %>%
    left_join(tcmb_df %>% mutate(YearMonth=format(Date,"%Y-%m")), by="YearMonth") %>%
    select(Date=Date.x, TCMB_Rate)
  cat(sprintf("  TCMB Rate: %d aylık → günlüğe dönüştürüldü\n", nrow(tcmb_df)))
}, error=function(e) {
  cat("  TCMB Rate çekilemedi:", conditionMessage(e), "\n")
  tcmb_daily <<- data.frame(Date=as.Date(garan_df$Date), TCMB_Rate=NA_real_)
})

# ═══ VERİ BİRLEŞTİRME ═══
garan_final <- garan_df %>%
  left_join(usdtry_df, by="Date") %>% left_join(oil_df, by="Date") %>%
  left_join(tcmb_daily %>% mutate(Date=as.character(Date)), by="Date")
garan_final$USDTRY <- zoo::na.locf(garan_final$USDTRY, na.rm=FALSE)
garan_final$Oil <- zoo::na.locf(garan_final$Oil, na.rm=FALSE)
garan_final$TCMB_Rate <- zoo::na.locf(garan_final$TCMB_Rate, na.rm=FALSE)
garan_final <- garan_final %>% drop_na()
N <- nrow(garan_final)
cat(sprintf("\nGARAN final veri: %d satır\n", N))

# ═══ BÖLÜM A: GARAN KORELASYON KIRILMASI ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BÖLÜM A: GARAN — TRAIN vs TEST KORELASYON ANALİZİ\n")
cat(strrep("=", 80), "\n", sep="")

i_split <- floor(N * 0.70)
train_data <- garan_final[1:i_split, ]
test_data  <- garan_final[(i_split+1):N, ]

cat(sprintf("  Train: %d satır (%s → %s)\n", nrow(train_data),
            train_data$Date[1], tail(train_data$Date,1)))
cat(sprintf("  Test:  %d satır (%s → %s)\n", nrow(test_data),
            test_data$Date[1], tail(test_data$Date,1)))

macro_vars <- c("USDTRY", "Oil", "TCMB_Rate")
target_var <- "Close"

corr_rows <- list()
for (mv in macro_vars) {
  cor_train <- cor(train_data[[target_var]], train_data[[mv]], use="complete.obs")
  cor_test  <- cor(test_data[[target_var]], test_data[[mv]], use="complete.obs")
  cor_diff  <- cor_test - cor_train

  # Log-return korelasyonu
  tr_ret <- diff(log(train_data[[target_var]])); tr_mv_ret <- diff(log(train_data[[mv]]))
  te_ret <- diff(log(test_data[[target_var]])); te_mv_ret <- diff(log(test_data[[mv]]))
  cor_train_ret <- cor(tr_ret, tr_mv_ret, use="complete.obs")
  cor_test_ret  <- cor(te_ret, te_mv_ret, use="complete.obs")

  cat(sprintf("\n  %s:\n", mv))
  cat(sprintf("    Fiyat korelasyonu:  Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train, cor_test, cor_diff))
  cat(sprintf("    Return korelasyonu: Train=%.3f  Test=%.3f  FARK=%.3f\n",
              cor_train_ret, cor_test_ret, cor_test_ret - cor_train_ret))

  corr_rows[[length(corr_rows)+1]] <- data.frame(
    market="BIST_GARAN", variable=mv, metric="price_level",
    cor_train=cor_train, cor_test=cor_test, cor_diff=cor_diff,
    stringsAsFactors=FALSE)
  corr_rows[[length(corr_rows)+1]] <- data.frame(
    market="BIST_GARAN", variable=mv, metric="log_return",
    cor_train=cor_train_ret, cor_test=cor_test_ret, cor_diff=cor_test_ret-cor_train_ret,
    stringsAsFactors=FALSE)
}

garan_corr_df <- do.call(rbind, corr_rows)
write.csv(garan_corr_df, file.path(OUTDIR_DIAG, "mcaware_corr_GARAN.csv"), row.names=FALSE)
cat("\n\nGARAN korelasyon CSV kaydedildi.\n")

# ═══ BÖLÜM B: THYAO vs GARAN vs AAPL KARŞILAŞTIRMA ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("BÖLÜM B: ÜÇ VARLIK KORELASYON KIRILMASI KARŞILAŞTIRMASI\n")
cat(strrep("=", 80), "\n", sep="")

# Mevcut THYAO ve AAPL sonuçlarını oku
thyao_corr_file <- file.path(OUTDIR_DIAG, "mcaware_corr_analysis.csv")
nasdaq_corr_file <- file.path(OUTDIR_DIAG, "mcaware_nasdaq_CORR.csv")

comparison_rows <- list()

# GARAN sonuçları (az önce hesapladık)
for (i in 1:nrow(garan_corr_df)) {
  if (garan_corr_df$metric[i] == "price_level") {
    comparison_rows[[length(comparison_rows)+1]] <- data.frame(
      market="BIST_GARAN",
      variable=garan_corr_df$variable[i],
      cor_train=garan_corr_df$cor_train[i],
      cor_test=garan_corr_df$cor_test[i],
      cor_diff=garan_corr_df$cor_diff[i],
      abs_diff=abs(garan_corr_df$cor_diff[i]),
      anti_prediktif="HAYIR (7/15, rastgele)",
      stringsAsFactors=FALSE)
  }
}

# THYAO sonuçları (mevcut CSV'den)
if (file.exists(thyao_corr_file)) {
  thyao_corr <- read.csv(thyao_corr_file)
  thyao_price <- thyao_corr[thyao_corr$metric == "price_level", ]
  for (i in 1:nrow(thyao_price)) {
    comparison_rows[[length(comparison_rows)+1]] <- data.frame(
      market="BIST_THYAO",
      variable=thyao_price$variable[i],
      cor_train=thyao_price$cor_train[i],
      cor_test=thyao_price$cor_test[i],
      cor_diff=thyao_price$cor_diff[i],
      abs_diff=abs(thyao_price$cor_diff[i]),
      anti_prediktif="EVET (118/120, p<10^-15)",
      stringsAsFactors=FALSE)
  }
}

# AAPL sonuçları (mevcut CSV'den)
if (file.exists(nasdaq_corr_file)) {
  nasdaq_corr <- read.csv(nasdaq_corr_file)
  aapl_rows <- nasdaq_corr[nasdaq_corr$market == "NASDAQ_AAPL", ]
  for (i in 1:nrow(aapl_rows)) {
    comparison_rows[[length(comparison_rows)+1]] <- data.frame(
      market="NASDAQ_AAPL",
      variable=aapl_rows$variable[i],
      cor_train=aapl_rows$cor_train[i],
      cor_test=aapl_rows$cor_test[i],
      cor_diff=aapl_rows$cor_diff[i],
      abs_diff=abs(aapl_rows$cor_diff[i]),
      anti_prediktif="HAYIR (0/6)",
      stringsAsFactors=FALSE)
  }
}

comparison_df <- do.call(rbind, comparison_rows)
write.csv(comparison_df, file.path(OUTDIR_DIAG, "mcaware_corr_COMPARISON.csv"), row.names=FALSE)

# ═══ SONUÇ TABLOSU ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.18 — KORELASYON KIRILMASI KARŞILAŞTIRMA TABLOSU\n")
cat(strrep("=", 80), "\n", sep="")

cat("\n  Varlık + Değişken        Cor_Train  Cor_Test   FARK     |FARK|  Anti-pred?\n")
cat("  ", strrep("-", 80), "\n", sep="")
for (i in 1:nrow(comparison_df)) {
  r <- comparison_df[i,]
  label <- sprintf("%-12s %-10s", r$market, r$variable)
  cat(sprintf("  %-25s  %+.3f     %+.3f    %+.3f   %.3f   %s\n",
              label, r$cor_train, r$cor_test, r$cor_diff, r$abs_diff,
              r$anti_prediktif))
}

# ═══ DÜRÜST YORUM ═══
cat("\n", strrep("=", 80), "\n", sep="")
cat("ADIM I.18 — DÜRÜST YORUM\n")
cat(strrep("=", 80), "\n", sep="")

# GARAN kırılma büyüklüğü ortalaması
garan_price <- garan_corr_df[garan_corr_df$metric == "price_level", ]
garan_mean_abs_diff <- mean(abs(garan_price$cor_diff))

cat(sprintf("\n  GARAN ortalama |kırılma|: %.3f\n", garan_mean_abs_diff))

# THYAO kırılma büyüklüğü
if (exists("thyao_price")) {
  thyao_mean_abs_diff <- mean(thyao_price$abs_diff)
} else {
  thyao_mean_abs_diff <- mean(c(0.496, 0.562, 0.117))
}
cat(sprintf("  THYAO ortalama |kırılma|: %.3f (önceki I.12'den)\n", thyao_mean_abs_diff))

# AAPL kırılma büyüklüğü
if (exists("aapl_rows")) {
  aapl_mean_abs_diff <- mean(aapl_rows$abs_diff)
} else {
  aapl_mean_abs_diff <- mean(c(0.760, 1.056, 0.935))
}
cat(sprintf("  AAPL  ortalama |kırılma|: %.3f (önceki I.13'den)\n", aapl_mean_abs_diff))

cat("\n  KARAR MATRİSİ:\n")
if (garan_mean_abs_diff < thyao_mean_abs_diff * 0.7) {
  cat("  [A] GARAN kırılması THYAO'dan KÜÇÜK → Y5 DESTEKLENİYOR\n")
  cat("      Makro-hassas varlıklarda büyük kırılma + anti-prediktif\n")
  cat("      Dağıtık hassas varlıklarda küçük kırılma + anti-prediktif yok\n")
} else if (garan_mean_abs_diff >= thyao_mean_abs_diff * 0.7 &&
           garan_mean_abs_diff <= thyao_mean_abs_diff * 1.3) {
  cat("  [B] GARAN kırılması THYAO ile BENZERİ → Y5 ZAYIFLIYOR\n")
  cat("      Benzer kırılma ama farklı davranış = kırılma TEK BAŞINA\n")
  cat("      yeterli değil. AAPL çelişkisine ek bir çelişki.\n")
  cat("      DÜRÜST RAPORLAMA: Bu sonuç Y5'i desteklemiyor.\n")
} else {
  cat("  [C] GARAN kırılması THYAO'dan BÜYÜK → Y5 ÇÜRÜTÜLDÜ\n")
  cat("      AAPL gibi büyük kırılma ama anti-prediktif yok.\n")
  cat("      DÜRÜST RAPORLAMA: Korelasyon kırılması açıklaması yetersiz.\n")
}

cat(sprintf("\n  NOT: AAPL'da kırılma EN BÜYÜK (ortalama %.3f) ama anti-prediktif\n", aapl_mean_abs_diff))
cat("  YOK. Bu, korelasyon kırılmasının GEREKLI ama YETERLİ OLMAYAN\n")
cat("  bir koşul olduğuna işaret eder. Ek faktörler (piyasa etkinliği,\n")
cat("  likidite, trader profili) rol oynuyor olabilir.\n")

cat(sprintf("\n  CSV'ler kaydedildi: %s\n", OUTDIR))
cat("    - mcaware_corr_GARAN.csv\n")
cat("    - mcaware_corr_COMPARISON.csv\n")
cat("\nADIM I.18 TAMAMLANDI.\n")
.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' )
cat("    - mcaware_corr_GARAN.csv\n")
cat("    - mcaware_corr_COMPARISON.csv\n")
cat("\nADIM I.18 TAMAMLANDI.\n")

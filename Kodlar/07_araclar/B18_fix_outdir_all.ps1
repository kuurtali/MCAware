################################################################################
# B18 FIX — Tüm R dosyalarında OUTDIR yollarını düzelt
# CSV türüne göre doğru Sonuclar/ alt klasörüne yönlendir
# Çalıştırma: PowerShell'den bu scripti source edin
################################################################################

$baseDir = "c:\Users\Kurt\Desktop\Proje\00_Tubitak"
Set-Location $baseDir

# --- Mapping: CSV pattern → subdirectory ---
# PREDICTIONS.csv  → predictions/
# THRESHOLD_GRID   → thresholds/
# SUMMARY/OPTIMAL/RESULTS/STRICT/CROSS_ARCH/CROSS_FUND/MATRIX → summaries/
# YHAT_STATS/SEED_REPORT/CORR/MI_/LABEL_CHECK/McNEMAR/CALIBRATION/COMPARISON → diagnostics/
# VOTES            → predictions/

$changedFiles = @()

# ============================================================
# PART 1: Prototipler (01_prototypes/) — OUTDIR <- here::here()
# ============================================================
$protoFiles = Get-ChildItem "Kodlar\01_prototypes\*.R"

foreach ($file in $protoFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $original = $content
    
    # 1a) OUTDIR <- here::here() → çoklu dizin tanımı
    # Eski fallback bloğunu da temizle
    $content = $content -replace '(?m)^OUTDIR\s*<-\s*here::here\(\)\s*#?[^\r\n]*', @"
OUTDIR_SUM  <- here::here("Sonuclar", "summaries")
OUTDIR_PRED <- here::here("Sonuclar", "predictions")
OUTDIR_THR  <- here::here("Sonuclar", "thresholds")
OUTDIR_DIAG <- here::here("Sonuclar", "diagnostics")
for (.d in c(OUTDIR_SUM, OUTDIR_PRED, OUTDIR_THR, OUTDIR_DIAG)) {
  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE)
}
"@

    # 1b) Fallback bloğunu kaldır (artık gerek yok)
    $content = $content -replace '(?ms)if \(!dir\.exists\(OUTDIR\)\) \{[^}]*OUTDIR\s*<-\s*WORKDIR[^}]*\}', '# (OUTDIR fallback blogu kaldirildi — B18 fix ile subdirectory tanimlari eklendi)'

    # 1c) file.path(OUTDIR, "..._PREDICTIONS.csv") → OUTDIR_PRED
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*PREDICTIONS[^)]*)\)', 'file.path(OUTDIR_PRED, $1)'
    
    # 1d) file.path(OUTDIR, "..._THRESHOLD_GRID.csv") → OUTDIR_THR
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*THRESHOLD_GRID[^)]*)\)', 'file.path(OUTDIR_THR, $1)'
    
    # 1e) file.path(OUTDIR, "..._YHAT_STATS.csv") → OUTDIR_DIAG
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*YHAT_STATS[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
    
    # 1f) file.path(OUTDIR, "..._SEED_REPORT.csv") → OUTDIR_DIAG
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*SEED_REPORT[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
    
    # 1g) file.path(OUTDIR, "..._CORR...csv") → OUTDIR_DIAG
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*_CORR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
    
    # 1h) file.path(OUTDIR, "..._McNEMAR.csv") → OUTDIR_DIAG
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*McNEMAR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
    
    # 1i) file.path(OUTDIR, "..._CROSS_ARCH_SUMMARY.csv") → OUTDIR_SUM (önce CROSS_ARCH yakala)
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*CROSS_ARCH[^)]*)\)', 'file.path(OUTDIR_SUM, $1)'
    
    # 1j) file.path(OUTDIR, "..._CROSS_FUND_SUMMARY.csv") → OUTDIR_SUM
    $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*CROSS_FUND[^)]*)\)', 'file.path(OUTDIR_SUM, $1)'
    
    # 1k) Kalan tüm file.path(OUTDIR, ...) → OUTDIR_SUM (SUMMARY, OPTIMAL, RESULTS)
    $content = $content -replace 'file\.path\(OUTDIR,', 'file.path(OUTDIR_SUM,'
    
    # 1l) cat("Cikti klasoru:", OUTDIR, ...) → OUTDIR_SUM
    $content = $content -replace 'cat\("Cikti klasoru:",\s*OUTDIR,', 'cat("Cikti klasoru:", OUTDIR_SUM,'
    
    # 1m) Sabit dosya adı (LSTM özel durum)
    $content = $content -replace 'write\.csv\(df_res,\s*"mcaware_LSTM_RESULTS\.csv"', 'write.csv(df_res, file.path(OUTDIR_SUM, "mcaware_LSTM_RESULTS.csv")'
    $content = $content -replace 'write\.csv\(summary_tbl,\s*"mcaware_LSTM_SUMMARY\.csv"', 'write.csv(summary_tbl, file.path(OUTDIR_SUM, "mcaware_LSTM_SUMMARY.csv")'
    
    if ($content -ne $original) {
        Set-Content $file.FullName $content -Encoding UTF8 -NoNewline
        $changedFiles += $file.Name
        Write-Host "[OK] $($file.Name)" -ForegroundColor Green
    } else {
        Write-Host "[--] $($file.Name) (degisiklik yok)" -ForegroundColor Yellow
    }
}

# ============================================================
# PART 2: Ablation, Validation, Baseline, Diagnostic, Ek Deneyler
# Bu dosyalarda OUTDIR <- here::here("Sonuclar") kalıbı var
# ============================================================
$otherDirs = @(
    "Kodlar\02_ablation",
    "Kodlar\03_validation",
    "Kodlar\04_baseline",
    "Kodlar\05_diagnostic",
    "Kodlar\06_ek_deneyler"
)

foreach ($dir in $otherDirs) {
    $files = Get-ChildItem "$dir\*.R" -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $original = $content
        
        # 2a) OUTDIR <- here::here("Sonuclar") → çoklu dizin
        $content = $content -replace '(?m)^OUTDIR\s*<-\s*here::here\("Sonuclar"\)\s*', @"
OUTDIR_SUM  <- here::here("Sonuclar", "summaries")
OUTDIR_PRED <- here::here("Sonuclar", "predictions")
OUTDIR_THR  <- here::here("Sonuclar", "thresholds")
OUTDIR_DIAG <- here::here("Sonuclar", "diagnostics")
for (.d in c(OUTDIR_SUM, OUTDIR_PRED, OUTDIR_THR, OUTDIR_DIAG)) {
  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE)
}

"@
        
        # 2b) if (!dir.exists(OUTDIR)) { dir.create(OUTDIR, ...) } → kaldır (yukarıda yapıldı)
        $content = $content -replace '(?m)^if \(!dir\.exists\(OUTDIR\)\)\s*\{\s*dir\.create\(OUTDIR,\s*recursive\s*=\s*TRUE\)\s*\}\s*\r?\n', ''

        # 2c) Aynı CSV-türü mapping'leri
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*PREDICTIONS[^)]*)\)', 'file.path(OUTDIR_PRED, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*THRESHOLD_GRID[^)]*)\)', 'file.path(OUTDIR_THR, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*YHAT_STATS[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*SEED_REPORT[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*SEED_VAR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*_CORR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*McNEMAR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*MI_SCORES[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*MI_CALIBRATION[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*LABEL_CHECK[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*COMPARISON[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*VOTES[^)]*)\)', 'file.path(OUTDIR_PRED, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*CROSS_ARCH[^)]*)\)', 'file.path(OUTDIR_SUM, $1)'
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*CROSS_FUND[^)]*)\)', 'file.path(OUTDIR_SUM, $1)'
        
        # 2d) Kalan tüm file.path(OUTDIR, ...) → OUTDIR_SUM
        $content = $content -replace 'file\.path\(OUTDIR,', 'file.path(OUTDIR_SUM,'
        
        if ($content -ne $original) {
            Set-Content $file.FullName $content -Encoding UTF8 -NoNewline
            $changedFiles += $file.Name
            Write-Host "[OK] $($file.Name)" -ForegroundColor Green
        } else {
            Write-Host "[--] $($file.Name) (degisiklik yok)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TOPLAM DEGISEN DOSYA: $($changedFiles.Count)" -ForegroundColor Cyan
Write-Host "Degisen dosyalar:" -ForegroundColor Cyan
$changedFiles | ForEach-Object { Write-Host "  $_" }
Write-Host "========================================" -ForegroundColor Cyan

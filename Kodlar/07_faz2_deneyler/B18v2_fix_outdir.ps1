################################################################################
# B18v2 — Tum R dosyalarinda OUTDIR yollarini duzelt (v2 - guvenilir)
# Strateji: Her dosyayi satirlar halinde oku, OUTDIR satirini bul, 
#           hemen altina yeni tanimlari ekle, eski satiri yorumla,
#           file.path(OUTDIR, ...) cagrilarini CSV turune gore degistir.
################################################################################

$baseDir = "c:\Users\Kurt\Desktop\Proje\00_Tubitak"
Set-Location $baseDir

$newDirBlock = @(
    '# --- B18 fix: Subdirectory tanimlari ---',
    'OUTDIR_SUM  <- here::here("Sonuclar", "summaries")',
    'OUTDIR_PRED <- here::here("Sonuclar", "predictions")',
    'OUTDIR_THR  <- here::here("Sonuclar", "thresholds")',
    'OUTDIR_DIAG <- here::here("Sonuclar", "diagnostics")',
    'for (.d in c(OUTDIR_SUM, OUTDIR_PRED, OUTDIR_THR, OUTDIR_DIAG)) {',
    '  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE)',
    '}'
)

# Hedef dizinler (FINAL_RELEASE zaten duzeldi)
$searchDirs = @(
    "Kodlar\01_prototypes",
    "Kodlar\02_ablation",
    "Kodlar\03_validation",
    "Kodlar\04_baseline",
    "Kodlar\05_diagnostic",
    "Kodlar\06_ek_deneyler"
)

$totalChanged = 0

foreach ($dir in $searchDirs) {
    $fullDir = Join-Path $baseDir $dir
    if (-not (Test-Path $fullDir)) { continue }
    $files = Get-ChildItem $fullDir -Filter "*.R"
    
    foreach ($file in $files) {
        $raw = [System.IO.File]::ReadAllText($file.FullName)
        
        # OUTDIR_SUM zaten varsa atla
        if ($raw -match 'OUTDIR_SUM') {
            Write-Host "[SKIP] $($file.Name) (zaten duzeltilmis)" -ForegroundColor DarkGray
            continue
        }
        
        # OUTDIR <- ... satiri var mi?
        if ($raw -notmatch 'OUTDIR\s*<-') {
            Write-Host "[SKIP] $($file.Name) (OUTDIR yok)" -ForegroundColor DarkGray
            continue
        }
        
        $lines = $raw -split "`n"
        $newLines = @()
        $inserted = $false
        
        foreach ($line in $lines) {
            # OUTDIR <- here::here(...) satirini bul
            if (-not $inserted -and $line -match '^\s*OUTDIR\s*<-\s*here::here\(') {
                $newLines += "# [B18] $line"  # eski satiri yorumla
                $newLines += $newDirBlock      # yeni blogu ekle
                $inserted = $true
            }
            # if (!dir.exists(OUTDIR)) fallback blogunu yorumla  
            elseif ($line -match 'if\s*\(\s*!dir\.exists\(OUTDIR\)\s*\)' -and $inserted) {
                $newLines += "# [B18] $line"
            }
            elseif ($line -match '^\s*OUTDIR\s*<-\s*WORKDIR' -and $inserted) {
                $newLines += "# [B18] $line"
            }
            else {
                $newLines += $line
            }
        }
        
        if (-not $inserted) {
            Write-Host "[SKIP] $($file.Name) (regex eslesme yok)" -ForegroundColor Yellow
            continue
        }
        
        # Simdi file.path(OUTDIR, ...) cagrilarini CSV turune gore degistir
        $content = $newLines -join "`n"
        
        # PREDICTIONS → OUTDIR_PRED
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*PREDICTIONS[^)]*)\)', 'file.path(OUTDIR_PRED, $1)'
        # THRESHOLD_GRID → OUTDIR_THR
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*THRESHOLD_GRID[^)]*)\)', 'file.path(OUTDIR_THR, $1)'
        # YHAT_STATS → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*YHAT_STATS[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # SEED_REPORT → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*SEED_REPORT[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # _CORR → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*_CORR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # McNEMAR → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*McNEMAR[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # MI_SCORES / MI_CALIBRATION → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*MI_[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # LABEL_CHECK → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*LABEL_CHECK[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # COMPARISON → OUTDIR_DIAG
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*COMPARISON[^)]*)\)', 'file.path(OUTDIR_DIAG, $1)'
        # VOTES → OUTDIR_PRED
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*VOTES[^)]*)\)', 'file.path(OUTDIR_PRED, $1)'
        # CROSS_ARCH / CROSS_FUND → OUTDIR_SUM
        $content = $content -replace 'file\.path\(OUTDIR,\s*([^)]*CROSS_[^)]*)\)', 'file.path(OUTDIR_SUM, $1)'
        # Kalan file.path(OUTDIR, ...) → OUTDIR_SUM (SUMMARY, OPTIMAL, RESULTS, STRICT)
        $content = $content -replace 'file\.path\(OUTDIR,', 'file.path(OUTDIR_SUM,'
        
        # cat("Cikti klasoru:", OUTDIR, ...) → OUTDIR_SUM
        $content = $content -replace 'cat\([^)]*OUTDIR[^)]*\)', { $_.Value -replace '\bOUTDIR\b', 'OUTDIR_SUM' }
        
        # Hardcoded LSTM writes
        $content = $content -replace 'write\.csv\(df_res,\s*"mcaware_LSTM_RESULTS\.csv"', 'write.csv(df_res, file.path(OUTDIR_SUM, "mcaware_LSTM_RESULTS.csv")'
        $content = $content -replace 'write\.csv\(summary_tbl,\s*"mcaware_LSTM_SUMMARY\.csv"', 'write.csv(summary_tbl, file.path(OUTDIR_SUM, "mcaware_LSTM_SUMMARY.csv")'
        
        [System.IO.File]::WriteAllText($file.FullName, $content)
        $totalChanged++
        Write-Host "[OK] $($file.Name)" -ForegroundColor Green
    }
}

# FINAL_RELEASE + 06_ek icin OUTDIR <- here::here("Sonuclar") olanlari da yakala
$extraDirs = @("Kodlar\06_ek_deneyler")
foreach ($dir in $extraDirs) {
    $fullDir = Join-Path $baseDir $dir
    if (-not (Test-Path $fullDir)) { continue }
    $files = Get-ChildItem $fullDir -Filter "*.R"
    foreach ($file in $files) {
        $raw = [System.IO.File]::ReadAllText($file.FullName)
        if ($raw -match 'OUTDIR_SUM') {
            # Eski OUTDIR <- here::here("Sonuclar") satirini yorumla
            if ($raw -match '(?m)^\s*OUTDIR\s*<-\s*here::here\("Sonuclar"\)') {
                $raw = $raw -replace '(?m)^(\s*OUTDIR\s*<-\s*here::here\("Sonuclar"\)[^\n]*)', '# [B18] $1'
                # dir.create(OUTDIR) satirini da yorumla
                $raw = $raw -replace '(?m)^(if \(!dir\.exists\(OUTDIR\)\)[^\n]*)', '# [B18] $1'
                [System.IO.File]::WriteAllText($file.FullName, $raw)
                Write-Host "[OK-extra] $($file.Name) (eski OUTDIR yorumlandi)" -ForegroundColor Cyan
            }
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TOPLAM DEGISEN DOSYA: $totalChanged" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

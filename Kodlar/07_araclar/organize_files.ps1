# Bu script zaten çalıştırıldı (23 Mayıs 2026). Arşiv olarak saklanmaktadır.
# Proje Dizinlerini ve Dosyalarını Organize Etme Scripti
$baseDir = "c:\Users\Kurt\Desktop\Proje\00_Tubitak"
Set-Location $baseDir

# Klasörleri Oluştur
$folders = @(
    "Kodlar/01_prototypes",
    "Kodlar/02_ablation",
    "Kodlar/03_validation",
    "Kodlar/04_baseline",
    "Kodlar/05_diagnostic",
    "Sonuclar/predictions",
    "Sonuclar/summaries",
    "Sonuclar/thresholds",
    "Sonuclar/diagnostics",
    "Docs"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }
}

# Docs Taşıma
Move-Item -Path "PROJE_DURUMU.txt" -Destination "Docs/" -ErrorAction SilentlyContinue
Move-Item -Path "PROJECT_REPORT.txt" -Destination "Docs/" -ErrorAction SilentlyContinue
Move-Item -Path "HOCA_BRIEF_v2.md" -Destination "Docs/" -ErrorAction SilentlyContinue
Move-Item -Path "HOCA_OZET.txt" -Destination "Docs/" -ErrorAction SilentlyContinue
Move-Item -Path "TUBITAK_2209A_Proje_Onerisi.pdf" -Destination "Docs/" -ErrorAction SilentlyContinue

# Kodlar Taşıma
Move-Item -Path "*prototype*.R" -Destination "Kodlar/01_prototypes/" -ErrorAction SilentlyContinue
Move-Item -Path "*ablation*.R" -Destination "Kodlar/02_ablation/" -ErrorAction SilentlyContinue
Move-Item -Path "*corr*.R" -Destination "Kodlar/02_ablation/" -ErrorAction SilentlyContinue
Move-Item -Path "*walkforward*.R" -Destination "Kodlar/03_validation/" -ErrorAction SilentlyContinue
Move-Item -Path "*nasdaq*.R" -Destination "Kodlar/03_validation/" -ErrorAction SilentlyContinue
Move-Item -Path "*multi_stock*.R" -Destination "Kodlar/03_validation/" -ErrorAction SilentlyContinue
Move-Item -Path "*rule_based*.R" -Destination "Kodlar/04_baseline/" -ErrorAction SilentlyContinue
Move-Item -Path "*ensemble*.R" -Destination "Kodlar/04_baseline/" -ErrorAction SilentlyContinue
Move-Item -Path "*diagnostic*.R" -Destination "Kodlar/05_diagnostic/" -ErrorAction SilentlyContinue
Move-Item -Path "*calibration*.R" -Destination "Kodlar/05_diagnostic/" -ErrorAction SilentlyContinue

# Sonuçlar Taşıma
Move-Item -Path "*PREDICTIONS.csv" -Destination "Sonuclar/predictions/" -ErrorAction SilentlyContinue
Move-Item -Path "*SUMMARY.csv" -Destination "Sonuclar/summaries/" -ErrorAction SilentlyContinue
Move-Item -Path "*OPTIMAL.csv" -Destination "Sonuclar/summaries/" -ErrorAction SilentlyContinue
Move-Item -Path "*RESULTS.csv" -Destination "Sonuclar/summaries/" -ErrorAction SilentlyContinue
Move-Item -Path "*THRESHOLD_GRID.csv" -Destination "Sonuclar/thresholds/" -ErrorAction SilentlyContinue
Move-Item -Path "*YHAT_STATS.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue
Move-Item -Path "*corr*.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue
Move-Item -Path "*CORR*.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue
Move-Item -Path "*MI_*.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue
Move-Item -Path "*LABEL_CHECK*.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue
Move-Item -Path "*McNEMAR*.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue
Move-Item -Path "*VOTES*.csv" -Destination "Sonuclar/predictions/" -ErrorAction SilentlyContinue
Move-Item -Path "*SEED_REPORT*.csv" -Destination "Sonuclar/diagnostics/" -ErrorAction SilentlyContinue

Write-Host "Organizasyon tamamlandi!"

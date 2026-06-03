################################################################################
# B17 FIX — Dashboard Google Fonts + CDN Embed (Offline Uyumlu)
# Dashboard'daki dış bağımlılıkları (Google Fonts, Chart.js CDN) yerel dosyalara çevirir
################################################################################

$DASHBOARD = "C:\Users\Kurt\Desktop\Proje\00_Tubitak\Docs\Dashboard"
$INDEX = "$DASHBOARD\index.html"

Write-Host "========== B17 FIX: Dashboard CDN -> Yerel =========="

if (-not (Test-Path $INDEX)) {
    Write-Host "[HATA] index.html bulunamadi: $INDEX"
    exit 1
}

# --- 1. Google Fonts CSS'ini indir ve yerel dosya olarak kaydet ---
Write-Host ""
Write-Host "1. Google Fonts CSS indiriliyor..."

$fontsDir = "$DASHBOARD\fonts"
if (-not (Test-Path $fontsDir)) {
    New-Item -Path $fontsDir -ItemType Directory -Force | Out-Null
}

# Inter ve Outfit font CSS'lerini indir
try {
    $fontsCss = Invoke-WebRequest -Uri "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Outfit:wght@400;500;600;700;800&display=swap" -UseBasicParsing
    $fontsCss.Content | Out-File "$fontsDir\google-fonts.css" -Encoding UTF8
    Write-Host "[OK] Google Fonts CSS indirildi: fonts/google-fonts.css"
} catch {
    Write-Host "[UYARI] Font CSS indirilemedi. Manuel olarak indirilmeli."
    # Fallback: system fonts CSS oluştur
    @"
/* B17 Fix: Offline fallback fonts */
@font-face { font-family: 'Inter'; font-style: normal; font-weight: 300 400 500 600 700; src: local('Inter'), local('Segoe UI'), local('Arial'); }
@font-face { font-family: 'Outfit'; font-style: normal; font-weight: 400 500 600 700 800; src: local('Outfit'), local('Segoe UI'), local('Arial'); }
"@ | Out-File "$fontsDir\google-fonts.css" -Encoding UTF8
    Write-Host "[OK] Fallback sistem fontu CSS olusturuldu"
}

# --- 2. Chart.js CDN'den indir ---
Write-Host ""
Write-Host "2. Chart.js indiriliyor..."

$jsDir = "$DASHBOARD\js"
if (-not (Test-Path $jsDir)) {
    New-Item -Path $jsDir -ItemType Directory -Force | Out-Null
}

try {
    Invoke-WebRequest -Uri "https://cdn.jsdelivr.net/npm/chart.js" -OutFile "$jsDir\chart.min.js" -UseBasicParsing
    Write-Host "[OK] Chart.js indirildi: js/chart.min.js"
} catch {
    Write-Host "[UYARI] Chart.js indirilemedi. Manuel indirme gerekli."
}

# --- 3. index.html'deki CDN referanslarini yerel dosyalara cevir ---
Write-Host ""
Write-Host "3. index.html CDN referanslari guncelleniyor..."

$content = Get-Content $INDEX -Raw -Encoding UTF8

# Google Fonts preconnect + link satırlarını değiştir
$content = $content -replace '<link rel="preconnect" href="https://fonts.googleapis.com">', '<!-- B17 fix: Google Fonts yerel -->'
$content = $content -replace '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>', ''
$content = $content -replace 'href="https://fonts.googleapis.com/css2[^"]*"', 'href="fonts/google-fonts.css"'

# Chart.js CDN'i yerel dosyaya çevir
$content = $content -replace 'src="https://cdn.jsdelivr.net/npm/chart\.js[^"]*"', 'src="js/chart.min.js"'

Set-Content $INDEX -Value $content -Encoding UTF8 -NoNewline
Write-Host "[OK] index.html guncellendi"

# --- 4. Kontrol ---
Write-Host ""
Write-Host "=== KONTROL ==="
Write-Host "Yerel dosyalar:"
Get-ChildItem -Path $fontsDir -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  fonts/$($_.Name) ($($_.Length) bytes)" }
Get-ChildItem -Path $jsDir -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  js/$($_.Name) ($($_.Length) bytes)" }

Write-Host ""
$remaining_cdn = Select-String -Path $INDEX -Pattern "cdn\.jsdelivr|fonts\.googleapis|fonts\.gstatic"
if ($remaining_cdn) {
    Write-Host "[UYARI] Hala CDN referansi var:"
    $remaining_cdn | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
} else {
    Write-Host "[OK] Tum CDN referanslari yerel dosyalara cevrildi!"
}

Write-Host ""
Write-Host "========== B17 FIX TAMAMLANDI =========="

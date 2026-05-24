################################################################################
# B6 FIX — Tüm R Scriptlerinde Hardcoded Yolları Göreceli Yola Çevir
# PowerShell'den çalıştır: powershell -ExecutionPolicy Bypass -File B6_fix_paths.ps1
################################################################################

$BASE = "C:\Users\Kurt\Desktop\Proje\00_Tubitak\Kodlar"
$OLD_WORKDIR = 'C:/Users/Kurt/Desktop'
$OLD_OUTDIR_1 = 'C:/Users/Kurt/Desktop/Proje/00_Tubitak/Sonuclar'
$OLD_OUTDIR_2 = 'C:/Users/Kurt/Desktop/Proje/00_Tubitak'

# Yeni göreceli yol yaklaşımı:
# here::here() paketi kullanılarak proje kök dizininden göreceli yollar
$NEW_HEADER = @'
# --- Gorecel Yol Ayari (B6 fix: hardcoded yollar kaldirildi) ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)
WORKDIR <- here::here()
OUTDIR  <- here::here("Sonuclar")
setwd(WORKDIR)
'@

Write-Host "========== B6 FIX: Hardcoded Yollar =========="
Write-Host ""

# Tüm R dosyalarını bul
$rfiles = Get-ChildItem -Path $BASE -Filter "*.R" -Recurse
Write-Host "Toplam R dosyasi: $($rfiles.Count)"
Write-Host ""

$fixed = 0
$skipped = 0

foreach ($file in $rfiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $original = $content
    
    # Hardcoded yol var mı kontrol et
    if ($content -match 'C:/Users/Kurt') {
        # WORKDIR satırını değiştir
        $content = $content -replace 'WORKDIR\s*<-\s*"C:/Users/Kurt/Desktop"', 'WORKDIR <- here::here()'
        
        # OUTDIR varyasyonlarını değiştir
        $content = $content -replace 'OUTDIR\s*<-\s*"C:/Users/Kurt/Desktop/Proje/00_Tubitak/Sonuclar"', 'OUTDIR <- here::here("Sonuclar")'
        $content = $content -replace 'OUTDIR\s*<-\s*"C:/Users/Kurt/Desktop/Proje/00_Tubitak"', 'OUTDIR <- here::here()'
        
        # Kalan hardcoded referansları değiştir
        $content = $content -replace 'C:/Users/Kurt/Desktop/Proje/00_Tubitak/Sonuclar', 'here::here("Sonuclar")'
        $content = $content -replace 'C:/Users/Kurt/Desktop/Proje/00_Tubitak', 'here::here()'
        $content = $content -replace 'C:/Users/Kurt/Desktop', 'here::here()'
        
        # here kütüphanesi yükleme satırı ekle (eğer yoksa)
        if ($content -notmatch 'library\(here\)') {
            # İlk satırın başına ekle (varolan comment'lerden sonra)
            $lines = $content -split "`n"
            $insertAt = 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^#') { $insertAt = $i + 1 }
                else { break }
            }
            $headerLines = @(
                '# --- B6 fix: here paketi ile gorecel yollar ---',
                'if (!require(here)) install.packages("here", repos="https://cran.r-project.org")',
                'library(here)',
                ''
            )
            $newLines = $lines[0..($insertAt-1)] + $headerLines + $lines[$insertAt..($lines.Count-1)]
            $content = $newLines -join "`n"
        }
        
        if ($content -ne $original) {
            Set-Content $file.FullName -Value $content -Encoding UTF8 -NoNewline
            Write-Host "[FIXED] $($file.FullName)"
            $fixed++
        } else {
            Write-Host "[SKIP]  $($file.FullName) (zaten duzeltilmis)"
            $skipped++
        }
    } else {
        Write-Host "[OK]    $($file.FullName) (hardcoded yol yok)"
        $skipped++
    }
}

Write-Host ""
Write-Host "========== B6 SONUC =========="
Write-Host "Duzeltilen: $fixed"
Write-Host "Atlanan:    $skipped"
Write-Host "Toplam:     $($rfiles.Count)"
Write-Host ""
Write-Host "NOT: 'here' paketi proje kok dizinini otomatik bulur."
Write-Host "     .Rproj veya .here dosyasi 00_Tubitak/ altinda olmalidir."
Write-Host ""

# .here dosyası oluştur (proje kök dizini işaretçisi)
$herefile = "C:\Users\Kurt\Desktop\Proje\00_Tubitak\.here"
if (-not (Test-Path $herefile)) {
    New-Item -Path $herefile -ItemType File -Force | Out-Null
    Write-Host "[OK] .here dosyasi olusturuldu: $herefile"
}

Write-Host "========== B6 FIX TAMAMLANDI =========="

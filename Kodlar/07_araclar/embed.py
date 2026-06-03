import os
import base64

html_path = r'c:\Users\Kurt\Desktop\Proje\00_Tubitak\Docs\Dashboard\index.html'
gorseller_dir = r'c:\Users\Kurt\Desktop\Proje\00_Tubitak\Gorseller'

with open(html_path, 'r', encoding='utf-8') as f:
    html = f.read()

image_names = [
    "01_Sektorel_Kiyaslama_Bar.png",
    "02_Anti_Prediktif_Scatter.png",
    "03_Correlation_Drift_Slope.png",
    "04_Feature_Ablation_Bar.png",
    "05_MC_Tuzagi_Cozumu.png",
    "06_Mimari_Kiyaslama.png",
    "07_WalkForward_Tutarsizlik.png",
    "08_Piyasa_Hassasiyet_Heatmap.png",
    "09_AntiPredictive_ROC_Curve.png",
    "10_Sektorel_Sıkı_Kriter_Bar.png",
    "11_Korelasyon_Paradoksu.png",
    "12_Walkforward_Inconsistency.png",
    "13_Seed_Invariance_Bulgusu.png",
    "14_AAPL_Klasik_ML_Karsilastirma.png",
    "15_IN_LEN_Ablasyonu.png",
    "16_WalkForward_MultiArch_Heatmap.png",
    "17_Sigorta_v1_vs_v2_Seed.png"
]

image_data_js = "const imageData = {\n"
for img_name in image_names:
    img_path = os.path.join(gorseller_dir, img_name)
    if os.path.exists(img_path):
        with open(img_path, 'rb') as img_f:
            b64_str = base64.b64encode(img_f.read()).decode('utf-8')
            data_uri = f"data:image/png;base64,{b64_str}"
            image_data_js += f'    "{img_name}": "{data_uri}",\n'
    else:
        # SVG fallback if image missing
        fallback = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="%231e293b"/><text x="50%" y="50%" font-family="sans-serif" font-size="14" fill="%2394a3b8" text-anchor="middle">Görsel bulunamadı</text></svg>'
        image_data_js += f'    "{img_name}": "{fallback}",\n'
image_data_js += "};\n"

# Replace the array with our dictionary mapping
html = html.replace('const imageNames = [', image_data_js + '\n    const imageNames = [')

# Replace the img src references
html = html.replace('`../../Gorseller/${img}`', 'imageData[img]')
html = html.replace('`../../Gorseller/${imgName}`', 'imageData[imgName]')

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(html)

print("Images successfully embedded into index.html!")

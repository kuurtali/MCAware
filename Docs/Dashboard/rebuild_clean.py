import os
import re
import base64

with open('index.html', 'r', encoding='utf-8') as f:
    html = f.read()

# Strip the large script block entirely
html_clean = re.sub(r'<script>.*?</script>', '', html, flags=re.DOTALL)
# Strip the style block entirely
html_clean = re.sub(r'<style>.*?</style>', '', html_clean, flags=re.DOTALL)

# Now we have clean HTML. Let's make sure there's a place to put our scripts and styles.
# We will inject the CSS in the <head>
with open('styles.css', 'r', encoding='utf-8') as f:
    css = f.read()

head_injection = f"<style>\n{css}\n</style>"
html_clean = html_clean.replace('</head>', head_injection + '\n</head>')

# We will inject the <img> tags directly into the galleryGrid
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

gorseller_dir = r'c:\Users\Kurt\Desktop\Proje\00_Tubitak\Gorseller'
gallery_html = ""
for img_name in image_names:
    img_path = os.path.join(gorseller_dir, img_name)
    if os.path.exists(img_path):
        with open(img_path, 'rb') as img_f:
            b64_str = base64.b64encode(img_f.read()).decode('utf-8')
            data_uri = f"data:image/png;base64,{b64_str}"
            gallery_html += f'<div class="gallery-item glass" onclick="openLightbox(\'{img_name}\')"><img src="{data_uri}" alt="{img_name}"></div>\n'
    else:
        fallback = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="%231e293b"/><text x="50%" y="50%" font-family="sans-serif" font-size="14" fill="%2394a3b8" text-anchor="middle">Görsel bulunamadı</text></svg>'
        gallery_html += f'<div class="gallery-item glass" onclick="openLightbox(\'{img_name}\')"><img src="{fallback}" alt="{img_name}"></div>\n'

html_clean = re.sub(r'<div class="gallery-grid" id="galleryGrid">.*?</div>', f'<div class="gallery-grid" id="galleryGrid">\n{gallery_html}\n</div>', html_clean, flags=re.DOTALL)

# Now we inject the safe JS at the end of the body
with open('app.js', 'r', encoding='utf-8') as f:
    js = f.read()

# Make JS robust to missing Chart.js
js_safe = """
document.addEventListener('DOMContentLoaded', () => {
    // Lightbox Logic
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightboxImg');
    const captionText = document.getElementById('caption');
    const closeBtn = document.querySelector('.close-btn');

    window.openLightbox = function(imgName) {
        lightbox.style.display = "block";
        const targetImg = document.querySelector(`img[alt="${imgName}"]`);
        if(targetImg) {
            lightboxImg.src = targetImg.src;
        }
        captionText.innerHTML = imgName.replace(/_/g, ' ').replace('.png', '');
    }

    closeBtn.onclick = () => { lightbox.style.display = "none"; }
    
    // Glossary Logic
    const glossaryBtn = document.getElementById('glossaryBtn');
    const glossaryModal = document.getElementById('glossaryModal');
    const closeGlossary = document.getElementById('closeGlossary');

    glossaryBtn.onclick = () => { glossaryModal.style.display = "block"; }
    closeGlossary.onclick = () => { glossaryModal.style.display = "none"; }
    
    window.onclick = (e) => { 
        if(e.target === lightbox) lightbox.style.display = "none"; 
        if(e.target === glossaryModal) glossaryModal.style.display = "none";
    }

    // Scroll Animations
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    }, { threshold: 0.1 });
    document.querySelectorAll('.section-reveal').forEach((el) => observer.observe(el));

    // Safely execute charts
    try {
        if (typeof Chart !== 'undefined') {
"""
# Extract just the chart generating code from app.js
chart_code = re.search(r"Chart\.defaults.*?// --- Gallery Population ---", js, flags=re.DOTALL)
if chart_code:
    js_safe += chart_code.group(0).replace("// --- Gallery Population ---", "")
    
js_safe += """
        } else {
            console.error('Chart.js failed to load. Graphics will not render, but layout will remain intact.');
        }
    } catch (error) {
        console.error('Error rendering charts:', error);
    }
});
"""

script_injection = f"<script>\n{js_safe}\n</script>\n</body>"
html_clean = html_clean.replace('</body>', script_injection)

# Make sure we don't have dangling <link> or <script src="app.js"> tags
html_clean = html_clean.replace('<link rel="stylesheet" href="styles.css">', '')
html_clean = html_clean.replace('<script src="app.js"></script>', '')

with open('index_fixed.html', 'w', encoding='utf-8') as f:
    f.write(html_clean)

print("index_fixed.html generated successfully.")

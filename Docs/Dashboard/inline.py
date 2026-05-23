import os

with open('index.html', 'r', encoding='utf-8') as f:
    html = f.read()

with open('styles.css', 'r', encoding='utf-8') as f:
    css = f.read()

with open('app.js', 'r', encoding='utf-8') as f:
    js = f.read()

html = html.replace('<link rel="stylesheet" href="styles.css">', f'<style>\n{css}\n</style>')
html = html.replace('<script src="app.js"></script>', f'<script>\n{js}\n</script>')

# Adding fallback for gallery images
fallback_js = """
    // Fallback for missing images
    document.querySelectorAll('.gallery-item img').forEach(img => {
        img.onerror = function() {
            this.onerror = null;
            this.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="%231e293b"/><text x="50%" y="50%" font-family="sans-serif" font-size="14" fill="%2394a3b8" text-anchor="middle">Görsel bulunamadı</text><text x="50%" y="60%" font-family="sans-serif" font-size="12" fill="%2364748b" text-anchor="middle">(Gorseller/ klasörü eksik)</text></svg>';
        };
    });
"""
html = html.replace('// Gallery Population ---', f'// Gallery Population ---\n{fallback_js}')

with open('index.html', 'w', encoding='utf-8') as f:
    f.write(html)

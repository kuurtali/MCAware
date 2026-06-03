from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
import os

doc = Document()
for s in doc.sections:
    s.top_margin=Cm(2.5); s.bottom_margin=Cm(2.5); s.left_margin=Cm(3); s.right_margin=Cm(2.5)

style = doc.styles['Normal']
style.font.name = 'Arial'
style.font.size = Pt(9)
style.paragraph_format.line_spacing = 1.15
style.paragraph_format.space_after = Pt(4)

for i in range(1,4):
    hs = doc.styles['Heading '+str(i)]
    hs.font.name = 'Arial'
    hs.font.color.rgb = RGBColor(0x1B, 0x3A, 0x5C)

# ========== GENEL BILGILER ==========
doc.add_heading('TÜBİTAK 2209-A SONUÇ RAPORU', level=0)
doc.add_paragraph()

t1 = doc.add_table(rows=4, cols=2, style='Light Shading Accent 1')
t1.alignment = WD_TABLE_ALIGNMENT.CENTER
data = [
    ('PROJENİN KONUSU', 'MC-AWARE: Derin Öğrenmede Anti-Prediktif Davranışın Çok Boyutlu Teşhisi'),
    ('PROJE YÜRÜTÜCÜSÜ', 'Mehmet Ali Kurt — Hacettepe Üniversitesi, Aktüerya Bilimleri'),
    ('DANIŞMAN', 'Öğr. Gör. Elif Ayaz'),
    ('PROJE TARİHLERİ', 'Başlangıç: Ekim 2025 — Bitiş: Haziran 2026')
]
for i, (k, v) in enumerate(data):
    t1.cell(i, 0).text = k
    t1.cell(i, 1).text = v
    for c in range(2):
        for r in t1.cell(i, c).paragraphs[0].runs:
            r.font.size = Pt(9)
            if c == 0: r.font.bold = True
doc.add_paragraph()

# ========== 1. GİRİŞ ==========
doc.add_heading('1. GİRİŞ', level=1)

p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Cm(0.75)
p.add_run(
    'Bu proje, TÜBİTAK 2209-A Lisans Araştırma Projeleri Destekleme Programı kapsamında, '
    'Borsa İstanbul (BIST) günlük yön tahmininde derin öğrenme modellerinin '
    'beklenmedik bir davranışını — anti-prediktif eğilimi — sistematik olarak tespit etmeyi '
    've çok boyutlu teşhisini gerçekleştirmeyi amaçlamaktadır.'
)

p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Cm(0.75)
p.add_run(
    'Anti-prediktif davranış, bir makine öğrenmesi modelinin rastgele tahminden (~%50) sistematik olarak '
    'daha kötü performans sergilemesi, yani tahminlerinin gerçek sonuçlarla negatif korelasyon göstermesi '
    'durumudur. Bu fenomen, modelin güçlü bir sinyal yakaladığını ancak bu sinyalin yönünün '
    'test döneminde tersine döndüğünü gösterir. Projemiz, bu fenomeni salt tespit etmekle kalmayıp, '
    'hangi koşullarda tetiklendiğini (sektör, pencere uzunluğu, makro değişken, dönem) '
    'sistematik olarak haritalamıştır.'
)

p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Cm(0.75)
p.add_run(
    'Projede 6 farklı derin öğrenme mimarisi (BiLSTM, GRU, Conv1D, TCN, Transformer, SimpleRNN) ile '
    "700'den fazla konfigürasyon, 11 BIST hissesi, 27 varlık ve 130 CSV çıktı üretilmiştir. "
    'Türk akademik literatüründe, derin öğrenme modellerinin Çoğunluk Sınıfı (MC) tuzağını '
    'sistematik olarak belgeleyen ve anti-prediktif davranışı çok boyutlu teşhis eden ilk çalışmadır.'
)

# ========== 2. YAPILAN CALISMALAR ==========
doc.add_heading('2. RAPOR DÖNEMLERİNDE YAPILAN ÇALIŞMALAR', level=1)

# Faz 1
doc.add_heading('2.1. Faz 1: Prototipleme ve İlk Deneyler (Ekim–Aralık 2025)', level=2)
for item in [
    'BiLSTM v1-v3 prototiplerinin geliştirilmesi ve THYAO hissesi üzerinde test edilmesi',
    'Makroekonomik değişkenlerin (USDTRY, Brent Petrol, TCMB Faiz) entegrasyonu',
    'MC tuzağının tespit edilmesi ve class_weight=balanced ile çözülmesi',
    'Anti-prediktif davranışın ilk kez gözlemlenmesi (~%40 model doğruluğu, ~%60 flip doğruluğu)',
    'İlk CSV çıktılarının üretilmesi ve analiz pipeline oluşturulması'
]:
    doc.add_paragraph(item, style='List Bullet')

# Faz 2
doc.add_heading('2.2. Faz 2: Ablasyon ve Diagnostik Deneyler (Ocak–Şubat 2026)', level=2)
for item in [
    'Özellik Grubu Ablasyonu: full_13 vs no_ext_10 — makro değişkenler çıkarılınca anti-prediktif davranış yok oldu',
    'Tekli Özellik Ablasyonu: Tek değişken çıkarıldığında etki yok → sinerjik sahte korelasyon kesin',
    'IN_LEN Ablasyonu v1 ve v2: IN_LEN ≤ 5 anti-prediktif tetikler, IN_LEN = 10 ortadan kaldırır',
    'MI Kalibrasyon: Karşılıklı Bilgi skorlarının histogram yanlılığı tespiti',
    'Label Check: Etiket doğrulama ve veri bütünlüğü kontrolü'
]:
    doc.add_paragraph(item, style='List Bullet')

# Faz 3
doc.add_heading('2.3. Faz 3: Çoklu Mimari Testi ve Walk-Forward (Mart–Nisan 2026)', level=2)
for item in [
    '6 DL mimarisinin (BiLSTM, GRU, Conv1D, TCN, Transformer, SimpleRNN) sistematik karşılaştırması',
    'McNemar testi ile mimariler arası istatistiksel fark analizi',
    '7-fold Walk-Forward v1 ve v2 doğrulama — val_data düzeltmesi',
    'Dönemsel anti-prediktif harita: Fold 2-3 (COVID) = %100, Fold 1,4,5 = %0',
    'Ensemble deneyleri: Hard Vote ve Soft Vote — anti-prediktif davranış korundu'
]:
    doc.add_paragraph(item, style='List Bullet')

# Faz 4
doc.add_heading('2.4. Faz 4: Çapraz Piyasa ve Çoklu Hisse Testleri (Nisan–Mayıs 2026)', level=2)
for item in [
    'NASDAQ (AAPL) vs BIST (THYAO) çapraz piyasa testi: BIST anti-prediktif, NASDAQ normal',
    '11 BIST hissesinde genişletilmiş test: 5 anti-prediktif, 6 normal/nötr',
    'Sektörel ayrışma kesin olarak kanıtlandı: havacılık + spekülatif → anti-prediktif, bankacılık → normal',
    'Bonferroni-düzeltilmiş p = 0.00012 ile istatistiksel anlamlılık',
    'Sigorta ve holding sektörlü testler (BES fonları dahil)'
]:
    doc.add_paragraph(item, style='List Bullet')

# Faz 5
doc.add_heading('2.5. Faz 5: Dokümantasyon ve Yayın Hazırlığı (Mayıs–Haziran 2026)', level=2)
for item in [
    'Literatür taraması: 25 bölüm, 30+ referans (Türk çalışmaları, uluslararası makaleler)',
    'Limitasyonlar: 15 kısıt ve 15 gelecek çalışma iş paketi',
    'Streamlit dashboard (10 tab, TR/EN dil desteği): app.py',
    'GitHub Pages statik dashboard: Docs/Dashboard/',
    '37 rapor görseli, 4 özel rapor görseli (G1-G4)',
    'Profesyonel dosya yapısı düzenleme ve GitHub push (248 dosya)'
]:
    doc.add_paragraph(item, style='List Bullet')

# ========== 3. SONUÇ ==========
doc.add_heading('3. SONUÇ', level=1)

p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Cm(0.75)
p.add_run(
    'Proje kapsamında gerçekleştirilen kapsamlı deneysel çalışma, '
    'derin öğrenme modellerinin gelişmekte olan piyasalarda (BIST) sistematik olarak '
    'anti-prediktif davranış sergileyebildiğini kesin olarak kanıtlamıştır. '
    'Aşağıdaki tablo, projenin temel özgün katkılarını özetlemektedir:'
)

doc.add_paragraph()
t2 = doc.add_table(rows=1, cols=2, style='Light Shading Accent 1')
t2.alignment = WD_TABLE_ALIGNMENT.CENTER
t2.cell(0,0).text = 'Bulgu'; t2.cell(0,1).text = 'Kanıt'
for r in t2.rows[0].cells[0].paragraphs[0].runs: r.font.bold=True; r.font.size=Pt(8)
for r in t2.rows[0].cells[1].paragraphs[0].runs: r.font.bold=True; r.font.size=Pt(8)

findings = [
    ('Anti-prediktif davranış', '700+ konfig., 6 mimari, ~%40 model → ~%60 flip'),
    ('Sektörel ayrışma', 'Havacılık/spekülatif: %100, bankacılık: normal'),
    ('Pencere uzunluğu etkisi', 'IN_LEN≤5: tetikler, IN_LEN=10: ortadan kaldırır'),
    ('Makro değişken mekanizması', 'USDTRY+Oil+TCMB çıkarılınca anomali yok'),
    ('Dönemsel harita', 'COVID (Fold 2-3): %100, Normal (Fold 1,4,5): %0'),
    ('Çapraz piyasa', 'BIST anti-prediktif, NASDAQ normal'),
    ('MC tuzağı çözümü', '700+ koşuda MC = 0'),
    ('Falsifikasyon', '11 hisselik stres testi, Bonferroni p = 0.00012'),
    ('İstatistiksel anlamlılık', 'Bireysel p < 0.0001, Bonferroni p = 0.00012'),
    ('Ensemble direnci', '6-mimari ensemble da anti-prediktif davranışı düzeltmedi')
]
for f, k in findings:
    row = t2.add_row()
    row.cells[0].text = f; row.cells[1].text = k
    for c in range(2):
        for r2 in row.cells[c].paragraphs[0].runs: r2.font.size=Pt(8)

doc.add_paragraph()
p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Cm(0.75)
p.add_run(
    'Sonuç olarak, projemiz derin öğrenme modellerinin finansal tahmin görevlerinde '
    '"her zaman daha iyi" olmadığını, aksine belirli makroekonomik koşullar altında '
    'sistematik olarak yanlış yöne tahmin yapabildiğini göstermiştir. '
    'Bu "anti-prediktif" davranış, literatürde henüz yeterince incelenmemiş '
    'kritik bir fenomendir ve projemiz bu boşluğu doldurmaktadır.'
)

p = doc.add_paragraph()
p.paragraph_format.first_line_indent = Cm(0.75)
p.add_run(
    'Projenin gelecek çalışmalarında, 15 iş paketi olarak belirlenen '
    'rejim algılama, seçici tahmin (Selective Abstain), çapraz piyasa doğrulama '
    've duygu analizi entegrasyonu gibi konuların araştırılması hedeflenmektedir.'
)

# ========== 4. CIKTILAR ==========
doc.add_heading('4. ÇIKTILAR (Yayınlar, Sunumlar vb.)', level=1)

outputs = [
    ('GitHub Deposu', 'https://github.com/kuurtali/Tubitak-2209A-MCAware — 248 dosya, 130 CSV'),
    ('Streamlit Dashboard', 'mcaware.streamlit.app — 10 tab, TR/EN, gerçek zamanlı interaktif panel'),
    ('Akademik Doküman', 'Literatur_ve_Limitasyonlar.docx — 25 literatür bölümü + 15 kısıt'),
    ('Rapor Görselleri', '37 görsel (PNG) + 4 özel rapor görseli'),
    ('Veri Çıktıları', '130 CSV: 71 özet + 19 tahmin + 26 diagnostik + 14 eşik grid'),
    ('R Scriptleri', '52 R scripti (7 klasör: prototip → araçlar)')
]
for title, desc in outputs:
    p = doc.add_paragraph()
    r = p.add_run(title + ': ')
    r.font.bold = True
    p.add_run(desc)

# ========== 5. HARCAMALAR ==========
doc.add_heading('5. HARCAMA KALEMLERİ', level=1)
p = doc.add_paragraph()
r = p.add_run('(Bu bölüm proje yürütücüsü tarafından doldurulacaktır.)')
r.italic = True

# ========== İMZA ==========
doc.add_paragraph()
doc.add_paragraph()
t3 = doc.add_table(rows=3, cols=2, style='Table Grid')
t3.alignment = WD_TABLE_ALIGNMENT.CENTER
t3.cell(0,0).text = 'PROJE YÜRÜTÜCÜSÜ'; t3.cell(0,1).text = 'DANIŞMAN'
t3.cell(1,0).text = 'Mehmet Ali Kurt'; t3.cell(1,1).text = 'Öğr. Gör. Elif Ayaz'
t3.cell(2,0).text = 'İmza:'; t3.cell(2,1).text = 'İmza:'
for r in range(3):
    for c in range(2):
        for run in t3.cell(r,c).paragraphs[0].runs:
            run.font.size = Pt(9)
            if r == 0: run.font.bold = True

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.add_run('Tarih: Haziran 2026')

outpath = 'Docs/TUBITAK_2209A_Sonuc_Raporu.docx'
doc.save(outpath)
sz = os.path.getsize(outpath) / 1024
print(f'Rapor: {sz:.1f} KB')
print('Bolumler: Giris + 5 Faz + Sonuc (10 bulgu tablosu) + Ciktilar + Harcama + Imza')

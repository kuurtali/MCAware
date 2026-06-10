"""MC-AWARE — Kapsamlı Bug Audit"""
import sys, os, ast, re
sys.stdout.reconfigure(encoding="utf-8")
os.chdir(os.path.join(os.path.dirname(__file__), "..", ".."))

bugs = []
warns = []

print("=" * 65)
print("  MC-AWARE GODMODE BUG AUDIT")
print("=" * 65)

# ============================================================
# 1. APP.PY SYNTAX
# ============================================================
print("\n[1/10] app.py SYNTAX...")
with open("app.py", encoding="utf-8") as f:
    src = f.read()
try:
    tree = ast.parse(src)
    print("  OK syntax")
except SyntaxError as e:
    bugs.append(f"CRITICAL: app.py syntax error: {e}")

# ============================================================
# 2. CSV FILE EXISTENCE (L() calls)
# ============================================================
print("\n[2/10] CSV referans kontrol...")
l_calls = re.findall(r'L\(\s*"([^"]+)"\s*,\s*"([^"]+)"', src)
for folder, fname in l_calls:
    path = os.path.join("Sonuclar", folder, fname)
    if not os.path.exists(path):
        bugs.append(f"MISSING CSV: {path}")
        print(f"  X {path}")
print(f"  {len(l_calls)} L() call, {len([1 for f,n in l_calls if not os.path.exists(os.path.join('Sonuclar',f,n))])} missing")

# ============================================================
# 3. IMAGE EXISTENCE (gallery)
# ============================================================
print("\n[3/10] Gorsel referans kontrol...")
img_refs = re.findall(r'\("(\d+_[^"]+\.png)"', src)
img_refs += re.findall(r'\("(G\d+_[^"]+\.png)"', src)
miss_img = [i for i in img_refs if not os.path.exists(os.path.join("Gorseller", i))]
for m in miss_img:
    bugs.append(f"MISSING IMAGE: {m}")
    print(f"  X {m}")
print(f"  {len(img_refs)} image ref, {len(miss_img)} missing")

# ============================================================
# 4. FILE COUNTS
# ============================================================
print("\n[4/10] Dosya sayilari...")
png_count = len([f for f in os.listdir("Gorseller") if f.endswith(".png")])
infog = os.path.join("Gorseller", "Infografikler")
infog_count = len([f for f in os.listdir(infog) if f.endswith(".png")]) if os.path.exists(infog) else 0

csv_total = 0
csv_detail = {}
for sub in ["summaries", "predictions", "diagnostics", "thresholds"]:
    p = os.path.join("Sonuclar", sub)
    c = len([f for f in os.listdir(p) if f.endswith(".csv")]) if os.path.exists(p) else 0
    csv_detail[sub] = c
    csv_total += c

code_count = 0
code_ext = {".R": 0, ".py": 0, ".ps1": 0}
for root, dirs, files in os.walk("Kodlar"):
    for f in files:
        ext = os.path.splitext(f)[1]
        if ext in code_ext:
            code_ext[ext] += 1
            code_count += 1

print(f"  PNG (Gorseller/): {png_count} (belge: 62)")
print(f"  PNG (Infografikler/): {infog_count}")
print(f"  CSV total: {csv_total} (belge: 130) -> {csv_detail}")
print(f"  Code files: {code_count} (belge: 61) -> {code_ext}")

if png_count != 62:
    warns.append(f"COUNT: {png_count} PNG vs documented 62")
if csv_total != 130:
    warns.append(f"COUNT: {csv_total} CSV vs documented 130")
if code_count != 61:
    warns.append(f"COUNT: {code_count} code vs documented 61")

# ============================================================
# 5. OLD REFERENCE SCAN (tüm dosyalar)
# ============================================================
print("\n[5/10] Eski referans taramasi...")
scan_files = ["app.py", "README.md", "Docs/PROJE_DURUMU.txt"]
old_patterns = ["5/11", "5 / 11", "52 gorsel", "52 PNG", "248 dosya"]
for fname in scan_files:
    if not os.path.exists(fname):
        continue
    with open(fname, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            for pat in old_patterns:
                if pat in line:
                    bugs.append(f"OLD REF: '{pat}' in {fname}:L{i}")
                    print(f"  X {fname}:L{i} -> '{pat}'")
            # check for 6 mimari but exclude comments about old versions
            if "6 mimari" in line.lower() and "v6" not in line and "6→7" not in line:
                warns.append(f"MAYBE OLD: '6 mimari' in {fname}:L{i}: {line.strip()[:80]}")
            if "11 hisse" in line and "BIST-11" not in line and "11→21" not in line:
                warns.append(f"MAYBE OLD: '11 hisse' in {fname}:L{i}: {line.strip()[:80]}")

# ============================================================
# 6. DOCX AUDIT
# ============================================================
print("\n[6/10] DOCX rapor kontrol...")
try:
    from docx import Document
    for docname in ["Docs/TUBITAK_2209A_Sonuc_Raporu.docx", "Docs/MC_AWARE_Kisisel_Rapor.docx"]:
        doc = Document(docname)
        text = " ".join([p.text for p in doc.paragraphs])
        short = os.path.basename(docname)
        for old in ["6 DL mimarisi", "6 farkli derin", "11 BIST", "52 gorsel", "5/11", "248 dosya"]:
            if old in text:
                bugs.append(f"OLD REF in {short}: '{old}'")
                print(f"  X {short}: '{old}'")
        # Check correct refs exist
        found_good = []
        for good in ["7 DL", "21 BIST", "7 farkli derin"]:
            if good in text:
                found_good.append(good)
        print(f"  {short}: correct refs = {found_good}")
except Exception as e:
    print(f"  SKIP docx: {e}")

# ============================================================
# 7. REQUIREMENTS CHECK
# ============================================================
print("\n[7/10] requirements.txt...")
with open("requirements.txt", encoding="utf-8") as f:
    reqs = [l.strip().split("==")[0].split(">=")[0].split("[")[0].lower()
            for l in f if l.strip() and not l.startswith("#")]
print(f"  Packages: {len(reqs)}")
# Check app.py actual imports
needed_pkgs = {"streamlit", "pandas", "plotly", "numpy"}
for n in needed_pkgs:
    status = "OK" if n in reqs else "MISSING"
    if status == "MISSING":
        bugs.append(f"MISSING REQUIREMENT: {n}")
    print(f"  {n}: {status}")

# ============================================================
# 8. DOCKERFILE CHECK
# ============================================================
print("\n[8/10] Dockerfile...")
with open("Dockerfile", encoding="utf-8") as f:
    df_content = f.read()
if "HEALTHCHECK" in df_content and "curl" in df_content:
    # Check if curl is installed
    if "curl" not in df_content.split("HEALTHCHECK")[0]:
        if "apt-get" in df_content and "curl" not in df_content.split("apt-get")[0]:
            warns.append("DOCKER: HEALTHCHECK uses curl but curl may not be installed")
            print("  WARN: curl for HEALTHCHECK may not be installed")
if "8501" in df_content:
    print("  OK port 8501")
if "app.py" in df_content:
    print("  OK entrypoint references app.py")

# ============================================================
# 9. R SCRIPT QUICK SCAN
# ============================================================
print("\n[9/10] R script hizli tarama...")
r_issues = []
for root, dirs, files in os.walk("Kodlar"):
    for fname in files:
        if not fname.endswith(".R"):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath, encoding="utf-8", errors="replace") as f:
                content = f.read()
            lines = content.split("\n")
            # Check for common issues
            if "OUTDIR" in content and "OUTDIR_SUM" not in content and "OUTDIR" in content:
                pass  # already checked
            if "TODO" in content or "FIXME" in content or "HACK" in content:
                for i, l in enumerate(lines, 1):
                    if any(t in l for t in ["TODO", "FIXME", "HACK"]):
                        r_issues.append(f"{fname}:L{i}: {l.strip()[:60]}")
            # Check for hardcoded paths
            for i, l in enumerate(lines, 1):
                if "C:\\" in l or "c:\\" in l or "Users\\" in l:
                    if not l.strip().startswith("#"):
                        r_issues.append(f"{fname}:L{i}: Hardcoded path: {l.strip()[:60]}")
        except Exception:
            pass

print(f"  R issues found: {len(r_issues)}")
for ri in r_issues[:15]:
    warns.append(f"R: {ri}")
    print(f"  WARN: {ri}")
if len(r_issues) > 15:
    print(f"  ... and {len(r_issues)-15} more")

# ============================================================
# 10. TRANSLATION COMPLETENESS
# ============================================================
print("\n[10/10] Ceviri tamam mi...")
t_calls = set(re.findall(r't\("([^"]+)"\)', src))
texts_keys = set(re.findall(r'"([^"]+)":\s*\{[^}]*"tr"', src))
missing_translations = t_calls - texts_keys
# This is approximate due to regex limitations
print(f"  t() unique keys: {len(t_calls)}")
if missing_translations:
    for m in list(missing_translations)[:5]:
        warns.append(f"TRANSLATION: t('{m}') key may be missing from TEXTS")
        print(f"  WARN: t('{m}') missing?")

# ============================================================
# SUMMARY
# ============================================================
print(f"\n{'=' * 65}")
print(f"  BUGS (kritik): {len(bugs)}")
print(f"  WARNINGS (uyari): {len(warns)}")
print(f"{'=' * 65}")

if bugs:
    print("\n  BUGS:")
    for i, b in enumerate(bugs, 1):
        print(f"  {i}. {b}")
else:
    print("\n  BUGS: YOK")

if warns:
    print("\n  WARNINGS:")
    for i, w in enumerate(warns, 1):
        print(f"  {i}. {w}")
else:
    print("\n  WARNINGS: YOK")

total = len(bugs) + len(warns)
if total == 0:
    print("\n  SONUC: PROJE TEMIZ!")
elif bugs:
    print(f"\n  SONUC: {len(bugs)} KRITIK BUG DUZELTILMELI")
else:
    print(f"\n  SONUC: Kritik bug yok, {len(warns)} uyari mevcut")

import re, sys
sys.stdout.reconfigure(encoding="utf-8")
with open("app.py", encoding="utf-8") as f:
    src = f.read()
t_calls = set(re.findall(r't\("([^"]+)"\)', src))
texts_block = src[src.find("TEXTS"):src.find("def t(")]
texts_keys = set(re.findall(r'"([^"]+)":\s*\{', texts_block))
missing = sorted(t_calls - texts_keys)
print(f"t() keys used: {len(t_calls)}")
print(f"TEXTS keys defined: {len(texts_keys)}")
print(f"Missing from TEXTS: {len(missing)}")
for m in missing:
    lines = [i for i, l in enumerate(src.split("\n"), 1) if f't("{m}")' in l]
    print(f'  t("{m}") at lines {lines[:3]}')

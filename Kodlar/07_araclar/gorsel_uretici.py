"""
MC-AWARE — CSV Verilerinden Görsel Üretici
Çalıştır: python Kodlar/07_araclar/gorsel_uretici.py
Çıktı: Gorseller/Infografikler/CSV_*.png
"""
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from pathlib import Path
import warnings
warnings.filterwarnings("ignore")

# --- Paths ---
BASE = Path(__file__).resolve().parent.parent.parent
SUM = BASE / "Sonuclar" / "summaries"
DIAG = BASE / "Sonuclar" / "diagnostics"
THR = BASE / "Sonuclar" / "thresholds"
OUT = BASE / "Gorseller" / "Infografikler"
OUT.mkdir(parents=True, exist_ok=True)

# --- Style ---
plt.rcParams.update({
    "figure.facecolor": "#0E1117",
    "axes.facecolor": "#1E1E2E",
    "axes.edgecolor": "#333",
    "axes.labelcolor": "#ccc",
    "text.color": "#eee",
    "xtick.color": "#aaa",
    "ytick.color": "#aaa",
    "grid.color": "#333",
    "grid.alpha": 0.5,
    "font.family": "sans-serif",
    "font.size": 11,
    "figure.dpi": 150,
})
RED = "#FF416C"
GREEN = "#00FF88"
ORANGE = "#FFA500"
CYAN = "#00BFFF"
PURPLE = "#9D4EDD"
YELLOW = "#FFD700"

def save(fig, name):
    p = OUT / name
    fig.savefig(p, bbox_inches="tight", pad_inches=0.3)
    plt.close(fig)
    print(f"  ✓ {name}")

# ===================================================================
# 1. TÜM HİSSELER — Sektörel Anti-Prediktif Harita
# ===================================================================
print("\n[1/10] Sektörel Anti-Prediktif Harita...")
try:
    macro = pd.read_csv(SUM / "mcaware_bist_ALL_macro_SUMMARY.csv")
    sig2 = pd.read_csv(SUM / "mcaware_bist5_sigorta_v2_SUMMARY.csv")
    hold = pd.read_csv(SUM / "mcaware_bist5_holding_SUMMARY.csv")

    # Birleştir
    rows = []
    for _, r in macro.iterrows():
        tk = r["ticker"].replace(".IS", "")
        rows.append({"ticker": tk, "acc": r["Acc_05"], "flip": r["Acc_flip_05"], "naive": r["naive"], "source": "BIST-11 Macro"})
    for _, r in sig2.iterrows():
        tk = r["ticker"].replace(".IS", "")
        rows.append({"ticker": tk, "acc": r["mean_acc"], "flip": r["mean_flip"], "naive": r["naive"], "source": "Sigorta"})
    for _, r in hold.iterrows():
        tk = r["ticker"].replace(".IS", "")
        rows.append({"ticker": tk, "acc": r["mean_acc"], "flip": r["mean_flip"], "naive": r["naive"], "source": "Holding"})

    df = pd.DataFrame(rows).sort_values("flip", ascending=False)

    fig, ax = plt.subplots(figsize=(14, 7))
    x = np.arange(len(df))
    w = 0.25
    bars_model = ax.bar(x - w, df["acc"], w, label="Model Acc", color=RED, alpha=0.9)
    bars_flip = ax.bar(x, df["flip"], w, label="Flip Acc", color=GREEN, alpha=0.9)
    bars_naive = ax.bar(x + w, df["naive"], w, label="Naive Acc", color=ORANGE, alpha=0.9)
    ax.axhline(y=0.5, color="white", linestyle="--", alpha=0.5, label="Şans (%50)")
    ax.set_xticks(x)
    ax.set_xticklabels(df["ticker"], rotation=45, ha="right", fontsize=10)
    ax.set_ylabel("Doğruluk", fontsize=12)
    ax.set_title("21 BIST Hissesi: Model vs Flip vs Naive (Sektörel Harita)", fontsize=14, fontweight="bold", color=RED)
    ax.legend(loc="upper right", fontsize=9, framealpha=0.3)
    ax.set_ylim(0.3, 0.7)
    ax.grid(axis="y", alpha=0.3)

    # Anti-prediktif olanları işaretle
    for i, row in enumerate(df.itertuples()):
        if row.flip > row.naive and row.acc < row.naive:
            ax.annotate("⚠️", (i, row.flip + 0.01), ha="center", fontsize=12)

    fig.tight_layout()
    save(fig, "CSV_01_Sektorel_Harita_21Hisse.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 2. 7 MİMARİ KARŞILAŞTIRMA
# ===================================================================
print("[2/10] 7 Mimari Karşılaştırma...")
try:
    arch = pd.read_csv(SUM / "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv")
    arch["arch_short"] = arch["arch"].str.replace("_ref", "").str.replace("BiLSTM_", "BiLSTM\n")

    fig, ax = plt.subplots(figsize=(12, 6))
    x = np.arange(len(arch))
    w = 0.25
    ax.bar(x - w, arch["mean_acc"], w, label="Model Acc", color=RED)
    ax.bar(x, arch["mean_acc_flip"], w, label="Flip Acc", color=GREEN)
    ax.bar(x + w, arch["naive_acc"], w, label="Naive Acc", color=ORANGE)
    ax.axhline(y=0.5, color="white", linestyle="--", alpha=0.5)
    ax.set_xticks(x)
    ax.set_xticklabels(arch["arch_short"], fontsize=9)
    ax.set_ylabel("Doğruluk")
    ax.set_title("7 DL Mimarisi: Hepsi Anti-Prediktif", fontsize=14, fontweight="bold", color=RED)
    ax.legend(fontsize=9, framealpha=0.3)
    ax.set_ylim(0.3, 0.7)
    ax.grid(axis="y", alpha=0.3)

    # MC count annotations
    for i, row in enumerate(arch.itertuples()):
        ax.text(i, row.mean_acc - 0.02, f"MC={int(row.mc_count)}", ha="center", fontsize=7, color="#aaa")

    save(fig, "CSV_02_7Mimari_Karsilastirma.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 3. WALK-FORWARD FOLD HARITASI
# ===================================================================
print("[3/10] Walk-Forward Fold Haritası...")
try:
    wf = pd.read_csv(SUM / "mcaware_walkforward_RESULTS.csv")

    fig, ax = plt.subplots(figsize=(12, 5))
    ax.plot(wf["fold"], wf["acc"], "o-", color=RED, linewidth=2.5, markersize=10, label="Model Acc", zorder=5)
    ax.plot(wf["fold"], wf["acc_flip"], "s-", color=GREEN, linewidth=2.5, markersize=10, label="Flip Acc", zorder=5)
    ax.plot(wf["fold"], wf["naive_acc"], "^--", color=ORANGE, linewidth=1.5, markersize=8, label="Naive Acc", zorder=4)
    ax.axhline(y=0.5, color="white", linestyle=":", alpha=0.4)
    ax.fill_between(wf["fold"], wf["acc"], 0.5, where=wf["acc"] < 0.5, alpha=0.15, color=RED)
    ax.fill_between(wf["fold"], wf["acc_flip"], 0.5, where=wf["acc_flip"] > 0.5, alpha=0.15, color=GREEN)

    ax.set_xlabel("Fold", fontsize=12)
    ax.set_ylabel("Doğruluk", fontsize=12)
    ax.set_title("Walk-Forward 7-Fold: Anti-Prediktif Dönemler", fontsize=14, fontweight="bold", color=RED)
    ax.legend(fontsize=10, framealpha=0.3)
    ax.set_xticks(wf["fold"])
    ax.grid(alpha=0.3)

    # Annotate extreme folds
    worst_idx = wf["acc"].idxmin()
    ax.annotate(f"En düşük\n{wf.loc[worst_idx, 'acc']:.3f}",
                xy=(wf.loc[worst_idx, "fold"], wf.loc[worst_idx, "acc"]),
                xytext=(wf.loc[worst_idx, "fold"] + 0.5, wf.loc[worst_idx, "acc"] - 0.04),
                arrowprops=dict(arrowstyle="->", color=RED), fontsize=9, color=RED)

    save(fig, "CSV_03_WalkForward_FoldHaritasi.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 4. KORELASYON KIRILMASI (Train vs Test)
# ===================================================================
print("[4/10] Korelasyon Kırılması...")
try:
    corr = pd.read_csv(DIAG / "mcaware_corr_COMPARISON.csv")

    fig, ax = plt.subplots(figsize=(10, 5))
    x = np.arange(len(corr))
    w = 0.35
    ax.bar(x - w/2, corr["cor_train"], w, label="Train Korelasyon", color=CYAN)
    ax.bar(x + w/2, corr["cor_test"], w, label="Test Korelasyon", color=RED)
    ax.set_xticks(x)
    ax.set_xticklabels(corr["variable"], fontsize=10)
    ax.set_ylabel("Pearson r")
    ax.set_title("Makro Değişken Korelasyonu: Train vs Test (Kırılma Noktası)", fontsize=13, fontweight="bold", color=RED)
    ax.legend(fontsize=10, framealpha=0.3)
    ax.grid(axis="y", alpha=0.3)

    # Draw arrows showing drop
    for i, row in enumerate(corr.itertuples()):
        drop = row.cor_train - row.cor_test
        if abs(drop) > 0.1:
            ax.annotate(f"Δ={drop:+.2f}", (i, max(row.cor_train, row.cor_test) + 0.03),
                        ha="center", fontsize=9, color=YELLOW, fontweight="bold")

    save(fig, "CSV_04_Korelasyon_Kirilmasi.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 5. ABLASYON: Feature Group + IN_LEN
# ===================================================================
print("[5/10] Ablasyon Çalışmaları...")
try:
    fa = pd.read_csv(SUM / "mcaware_feature_ablation_SUMMARY.csv")
    il = pd.read_csv(SUM / "mcaware_inlen_ablation_v2_SUMMARY.csv")

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Feature ablation
    x = np.arange(len(fa))
    w = 0.25
    ax1.bar(x - w, fa["mean_acc"], w, label="Model", color=RED)
    ax1.bar(x, fa["mean_flip"], w, label="Flip", color=GREEN)
    ax1.bar(x + w, fa["naive"], w, label="Naive", color=ORANGE)
    ax1.axhline(y=0.5, color="white", linestyle="--", alpha=0.4)
    ax1.set_xticks(x)
    ax1.set_xticklabels(fa["group"], fontsize=9)
    ax1.set_title("Özellik Grubu Ablasyonu", fontsize=12, fontweight="bold", color=CYAN)
    ax1.legend(fontsize=8, framealpha=0.3)
    ax1.set_ylim(0.3, 0.7)
    ax1.grid(axis="y", alpha=0.3)

    # IN_LEN ablation
    x2 = np.arange(len(il))
    ax2.bar(x2 - w, il["mean_acc"], w, label="Model", color=RED)
    ax2.bar(x2, il["mean_flip"], w, label="Flip", color=GREEN)
    ax2.bar(x2 + w, il["naive"], w, label="Naive", color=ORANGE)
    ax2.axhline(y=0.5, color="white", linestyle="--", alpha=0.4)
    ax2.set_xticks(x2)
    ax2.set_xticklabels([f"IN_LEN={v}" for v in il["IN_LEN"]], fontsize=9)
    ax2.set_title("Pencere Uzunluğu Ablasyonu (v2)", fontsize=12, fontweight="bold", color=CYAN)
    ax2.legend(fontsize=8, framealpha=0.3)
    ax2.set_ylim(0.3, 0.7)
    ax2.grid(axis="y", alpha=0.3)

    fig.suptitle("Ablasyon Çalışmaları: Neden Anti-Prediktif?", fontsize=14, fontweight="bold", color=RED, y=1.02)
    fig.tight_layout()
    save(fig, "CSV_05_Ablasyon_Calismalari.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 6. ENSEMBLE — Oy Dağılımı
# ===================================================================
print("[6/10] Ensemble Analizi...")
try:
    ens = pd.read_csv(SUM / "mcaware_ensemble_RESULTS.csv")

    fig, ax = plt.subplots(figsize=(12, 5))
    colors = [RED if row["Acc"] < 0.5 else GREEN for _, row in ens.iterrows()]
    x = np.arange(len(ens))
    ax.bar(x, ens["Acc"], 0.35, label="Model Acc", color=colors, alpha=0.9)
    ax.bar(x + 0.35, ens["Acc_flip"], 0.35, label="Flip Acc", color=[GREEN]*len(ens), alpha=0.6)
    ax.axhline(y=0.5, color="white", linestyle="--", alpha=0.5)
    ax.set_xticks(x + 0.175)
    ax.set_xticklabels(ens["name"], rotation=30, ha="right", fontsize=9)
    ax.set_ylabel("Doğruluk")
    ax.set_title("Ensemble Sonuçları: Hard+Soft Vote da Anti-Prediktif", fontsize=13, fontweight="bold", color=RED)
    ax.legend(fontsize=9, framealpha=0.3)
    ax.grid(axis="y", alpha=0.3)
    save(fig, "CSV_06_Ensemble_Sonuclari.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 7. CROSS-MARKET: BIST vs NASDAQ
# ===================================================================
print("[7/10] Cross-Market (BIST vs NASDAQ)...")
try:
    nq = pd.read_csv(SUM / "mcaware_nasdaq_SUMMARY.csv")

    fig, ax = plt.subplots(figsize=(10, 5))
    labels = nq["market"] + "\n" + nq["group"]
    x = np.arange(len(nq))
    w = 0.3
    bar_colors_model = [RED if "BIST" in m else CYAN for m in nq["market"]]
    bar_colors_flip = [GREEN if "BIST" in m else "#66BB6A" for m in nq["market"]]
    ax.bar(x - w/2, nq["mean_acc"], w, label="Model Acc", color=bar_colors_model)
    ax.bar(x + w/2, nq["mean_flip"], w, label="Flip Acc", color=bar_colors_flip)
    ax.axhline(y=0.5, color="white", linestyle="--", alpha=0.5)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("Doğruluk")
    ax.set_title("BIST vs NASDAQ: Anti-Prediktif Davranış Gelişmekte Olan Piyasaya Özgü",
                 fontsize=12, fontweight="bold", color=RED)
    ax.legend(fontsize=9, framealpha=0.3)
    ax.set_ylim(0.3, 0.7)
    ax.grid(axis="y", alpha=0.3)

    # Annotate
    ax.annotate("Anti-Prediktif!", xy=(0, nq.iloc[0]["mean_acc"]),
                xytext=(0.3, 0.35), arrowprops=dict(arrowstyle="->", color=RED),
                fontsize=10, color=RED, fontweight="bold")
    ax.annotate("Normal", xy=(2, nq.iloc[2]["mean_acc"]),
                xytext=(2.3, 0.58), arrowprops=dict(arrowstyle="->", color=GREEN),
                fontsize=10, color=GREEN, fontweight="bold")

    save(fig, "CSV_07_BIST_vs_NASDAQ.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 8. THRESHOLD HEATMAP (THYAO)
# ===================================================================
print("[8/10] Threshold Heatmap (THYAO)...")
try:
    thr = pd.read_csv(THR / "mcaware_BiLSTM_v3THYAO_THRESHOLD_GRID.csv")
    pivot = thr.groupby(["lambda", "threshold"])["Acc_test"].mean().reset_index()
    piv = pivot.pivot(index="lambda", columns="threshold", values="Acc_test")

    fig, ax = plt.subplots(figsize=(12, 5))
    im = ax.imshow(piv.values, cmap="RdYlGn", aspect="auto", vmin=0.3, vmax=0.7)
    ax.set_xticks(range(len(piv.columns)))
    ax.set_xticklabels([f"{c:.2f}" for c in piv.columns], fontsize=8, rotation=45)
    ax.set_yticks(range(len(piv.index)))
    ax.set_yticklabels([f"λ={r}" for r in piv.index], fontsize=9)
    ax.set_xlabel("Eşik (Threshold)")
    ax.set_ylabel("Lambda (λ)")
    ax.set_title("THYAO: Threshold × Lambda → Test Doğruluğu Isı Haritası", fontsize=13, fontweight="bold", color=RED)
    cbar = fig.colorbar(im, ax=ax, shrink=0.8)
    cbar.set_label("Acc_test", color="#ccc")
    cbar.ax.yaxis.set_tick_params(color="#aaa")
    plt.setp(plt.getp(cbar.ax.axes, "yticklabels"), color="#aaa")

    # Annotate values
    for i in range(piv.shape[0]):
        for j in range(piv.shape[1]):
            v = piv.values[i, j]
            if not np.isnan(v):
                color = "black" if v > 0.5 else "white"
                ax.text(j, i, f"{v:.2f}", ha="center", va="center", fontsize=6, color=color)

    save(fig, "CSV_08_Threshold_Heatmap_THYAO.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 9. McNEMAR TEST MATRİSİ
# ===================================================================
print("[9/10] McNemar Test Matrisi...")
try:
    mcn = pd.read_csv(DIAG / "mcaware_multi_arch_McNEMAR.csv")
    archs = sorted(set(mcn["arch1"].tolist() + mcn["arch2"].tolist()))
    n = len(archs)
    mat = np.ones((n, n))
    for _, row in mcn.iterrows():
        i = archs.index(row["arch1"])
        j = archs.index(row["arch2"])
        mat[i, j] = row["p_value"]
        mat[j, i] = row["p_value"]

    fig, ax = plt.subplots(figsize=(9, 7))
    im = ax.imshow(mat, cmap="RdYlGn", vmin=0, vmax=1)
    ax.set_xticks(range(n))
    ax.set_xticklabels([a.replace("BiLSTM_", "BiLSTM\n") for a in archs], fontsize=8, rotation=45, ha="right")
    ax.set_yticks(range(n))
    ax.set_yticklabels([a.replace("BiLSTM_", "BiLSTM\n") for a in archs], fontsize=8)
    ax.set_title("McNemar Testi: Mimariler Arası p-değeri (< 0.05 = Anlamlı Fark)", fontsize=12, fontweight="bold", color=CYAN)
    cbar = fig.colorbar(im, ax=ax, shrink=0.8)
    cbar.set_label("p-value", color="#ccc")

    for i in range(n):
        for j in range(n):
            color = "white" if mat[i, j] < 0.3 else "black"
            sig = "★" if mat[i, j] < 0.05 else ""
            ax.text(j, i, f"{mat[i,j]:.3f}{sig}", ha="center", va="center", fontsize=7, color=color)

    save(fig, "CSV_09_McNemar_Matrisi.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

# ===================================================================
# 10. TEKNİK İNDİKATÖRLER vs DL
# ===================================================================
print("[10/10] Teknik İndikatörler vs DL...")
try:
    ti = pd.read_csv(SUM / "mcaware_majority_rules_10ind_SUMMARY.csv")
    ti = ti.sort_values("accuracy", ascending=True)

    fig, ax = plt.subplots(figsize=(10, 6))
    colors = [GREEN if a > ti.iloc[0]["naive_acc"] else RED for a in ti["accuracy"]]
    bars = ax.barh(ti["method"], ti["accuracy"], color=colors, alpha=0.85)
    ax.axvline(x=ti.iloc[0]["naive_acc"], color=ORANGE, linestyle="--", linewidth=2, label=f"Naive ({ti.iloc[0]['naive_acc']:.2f})")
    ax.axvline(x=0.5, color="white", linestyle=":", alpha=0.4, label="Şans (%50)")
    ax.set_xlabel("Doğruluk")
    ax.set_title("Teknik İndikatörler: Rule-Based Baseline'larda Anti-Prediktif YOK",
                 fontsize=12, fontweight="bold", color=GREEN)
    ax.legend(fontsize=9, loc="lower right", framealpha=0.3)
    ax.grid(axis="x", alpha=0.3)

    for bar, acc in zip(bars, ti["accuracy"]):
        ax.text(bar.get_width() + 0.005, bar.get_y() + bar.get_height()/2,
                f"{acc:.3f}", va="center", fontsize=9, color="#ddd")

    save(fig, "CSV_10_Teknik_Indikatorler.png")
except Exception as e:
    print(f"  ✗ Hata: {e}")

print(f"\n{'='*60}")
print(f"Tüm görseller kaydedildi: {OUT}")
print(f"{'='*60}")

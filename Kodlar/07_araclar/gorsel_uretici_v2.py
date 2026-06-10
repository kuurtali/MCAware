"""
MC-AWARE — Eksik CSV Görselleri Üretici (Part 2)
Mevcut 52 görsele ek olarak 10 yeni veri-tabanlı görsel üretir.
Çalıştır: python Kodlar/07_araclar/gorsel_uretici_v2.py
"""
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from pathlib import Path
import warnings, glob
warnings.filterwarnings("ignore")

BASE = Path(__file__).resolve().parent.parent.parent
SUM  = BASE / "Sonuclar" / "summaries"
DIAG = BASE / "Sonuclar" / "diagnostics"
THR  = BASE / "Sonuclar" / "thresholds"
PRED = BASE / "Sonuclar" / "predictions"
OUT  = BASE / "Gorseller"
OUT.mkdir(parents=True, exist_ok=True)

plt.rcParams.update({
    "figure.facecolor": "#0E1117", "axes.facecolor": "#1E1E2E",
    "axes.edgecolor": "#333", "axes.labelcolor": "#ccc",
    "text.color": "#eee", "xtick.color": "#aaa", "ytick.color": "#aaa",
    "grid.color": "#333", "grid.alpha": 0.5, "font.size": 11,
    "figure.dpi": 150,
})
RED="#FF416C"; GREEN="#00FF88"; ORANGE="#FFA500"; CYAN="#00BFFF"
PURPLE="#9D4EDD"; YELLOW="#FFD700"; PINK="#FF69B4"

def save(fig, name):
    p = OUT / name
    fig.savefig(p, bbox_inches="tight", pad_inches=0.3)
    plt.close(fig)
    print(f"  ✓ {name}")

# ===================================================================
# 49. Sigorta + Holding Birleşik Sektörel Karşılaştırma
# ===================================================================
print("\n[49] Sigorta + Holding Birleşik...")
try:
    sig = pd.read_csv(SUM / "mcaware_bist5_sigorta_v2_SUMMARY.csv")
    hld = pd.read_csv(SUM / "mcaware_bist5_holding_SUMMARY.csv")

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5), sharey=True)

    # Sigorta
    sig["tk"] = sig["ticker"].str.replace(".IS", "")
    x = np.arange(len(sig))
    w = 0.25
    ax1.bar(x-w, sig["mean_acc"], w, label="Model", color=RED)
    ax1.bar(x, sig["mean_flip"], w, label="Flip", color=GREEN)
    ax1.bar(x+w, sig["naive"], w, label="Naive", color=ORANGE)
    ax1.axhline(0.5, color="white", ls="--", alpha=0.4)
    ax1.set_xticks(x); ax1.set_xticklabels(sig["tk"], fontsize=10)
    ax1.set_title("Sigorta Sektörü (5 Hisse)", fontsize=12, fontweight="bold", color=PINK)
    ax1.legend(fontsize=8, framealpha=0.3); ax1.set_ylim(0.35, 0.65)
    ax1.set_ylabel("Doğruluk"); ax1.grid(axis="y", alpha=0.3)
    for i, r in enumerate(sig.itertuples()):
        if hasattr(r, "siki_anti_pred") and r.siki_anti_pred:
            ax1.annotate("⚠️ AP", (i, r.mean_flip+0.01), ha="center", fontsize=9, color=RED)

    # Holding
    hld["tk"] = hld["ticker"].str.replace(".IS", "")
    x2 = np.arange(len(hld))
    ax2.bar(x2-w, hld["mean_acc"], w, label="Model", color=RED)
    ax2.bar(x2, hld["mean_flip"], w, label="Flip", color=GREEN)
    ax2.bar(x2+w, hld["naive"], w, label="Naive", color=ORANGE)
    ax2.axhline(0.5, color="white", ls="--", alpha=0.4)
    ax2.set_xticks(x2); ax2.set_xticklabels(hld["tk"], fontsize=10)
    ax2.set_title("Holding Sektörü (5 Hisse)", fontsize=12, fontweight="bold", color=CYAN)
    ax2.legend(fontsize=8, framealpha=0.3); ax2.grid(axis="y", alpha=0.3)

    fig.suptitle("Sektörel Karşılaştırma: Sigorta (2 AP) vs Holding (0 AP)", fontsize=14, fontweight="bold", color=RED)
    fig.tight_layout()
    save(fig, "49_Sigorta_vs_Holding_Detay.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 50. Flip > Naive Scatter (21 hisse)
# ===================================================================
print("[50] Flip>Naive Scatter 21 Hisse...")
try:
    macro = pd.read_csv(SUM / "mcaware_bist_ALL_macro_SUMMARY.csv")
    sig = pd.read_csv(SUM / "mcaware_bist5_sigorta_v2_SUMMARY.csv")
    hld = pd.read_csv(SUM / "mcaware_bist5_holding_SUMMARY.csv")

    rows = []
    for _, r in macro.iterrows():
        rows.append({"ticker": r["ticker"].replace(".IS",""), "acc": r["Acc_05"], "flip": r["Acc_flip_05"],
                      "naive": r["naive"], "group": "BIST-11 Macro"})
    for _, r in sig.iterrows():
        rows.append({"ticker": r["ticker"].replace(".IS",""), "acc": r["mean_acc"], "flip": r["mean_flip"],
                      "naive": r["naive"], "group": "Sigorta"})
    for _, r in hld.iterrows():
        rows.append({"ticker": r["ticker"].replace(".IS",""), "acc": r["mean_acc"], "flip": r["mean_flip"],
                      "naive": r["naive"], "group": "Holding"})
    df = pd.DataFrame(rows)

    fig, ax = plt.subplots(figsize=(10, 8))
    colors = {"BIST-11 Macro": RED, "Sigorta": PINK, "Holding": CYAN}
    for grp, sub in df.groupby("group"):
        ax.scatter(sub["acc"], sub["flip"], c=colors[grp], s=120, label=grp, edgecolors="white", linewidths=0.5, zorder=5)

    for _, r in df.iterrows():
        offset = (0.003, 0.005) if r["flip"] > 0.52 else (0.003, -0.012)
        ax.annotate(r["ticker"], (r["acc"]+offset[0], r["flip"]+offset[1]), fontsize=8, color="#ddd")

    ax.plot([0.3, 0.7], [0.3, 0.7], "--", color="#555", alpha=0.5)  # diagonal
    ax.axhline(0.5, color=GREEN, ls=":", alpha=0.3)
    ax.axvline(0.5, color=RED, ls=":", alpha=0.3)
    ax.fill_between([0.3, 0.5], 0.5, 0.7, alpha=0.05, color=RED)  # anti-predictive zone
    ax.text(0.42, 0.62, "Anti-Prediktif\nBölge", ha="center", fontsize=10, color=RED, alpha=0.7, fontweight="bold")
    ax.set_xlabel("Model Doğruluğu (Acc)", fontsize=12)
    ax.set_ylabel("Flip Doğruluğu", fontsize=12)
    ax.set_title("21 BIST Hissesi: Model Acc vs Flip Acc Scatter", fontsize=14, fontweight="bold", color=RED)
    ax.legend(fontsize=10, framealpha=0.3)
    ax.set_xlim(0.38, 0.6); ax.set_ylim(0.38, 0.65)
    ax.grid(alpha=0.3)
    save(fig, "50_FlipVsAcc_Scatter_21Hisse.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 51. WF v2 Multi-Arch Heatmap (fold × arch)
# ===================================================================
print("[51] WF v2 Multi-Arch Heatmap...")
try:
    wf = pd.read_csv(SUM / "mcaware_walkforward_multi_arch_v2_RESULTS.csv")
    pivot = wf.groupby(["fold", "arch"])["acc_flip"].mean().reset_index()
    piv = pivot.pivot(index="arch", columns="fold", values="acc_flip")

    fig, ax = plt.subplots(figsize=(12, 5))
    im = ax.imshow(piv.values, cmap="RdYlGn", aspect="auto", vmin=0.3, vmax=0.7)
    ax.set_xticks(range(piv.shape[1]))
    ax.set_xticklabels([f"Fold {c}" for c in piv.columns], fontsize=10)
    ax.set_yticks(range(piv.shape[0]))
    ax.set_yticklabels(piv.index, fontsize=9)
    ax.set_title("Walk-Forward v2: Fold × Mimari → Flip Accuracy", fontsize=13, fontweight="bold", color=RED)
    cbar = fig.colorbar(im, ax=ax, shrink=0.8)
    cbar.set_label("Flip Acc", color="#ccc")
    for i in range(piv.shape[0]):
        for j in range(piv.shape[1]):
            v = piv.values[i, j]
            if not np.isnan(v):
                col = "black" if v > 0.55 else "white"
                ax.text(j, i, f"{v:.3f}", ha="center", va="center", fontsize=8, color=col)
    save(fig, "51_WF_v2_FoldXMimari_Heatmap.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 52. YHAT Dağılım (Violin — çoklu mimari)
# ===================================================================
print("[52] YHAT Dağılım Violin...")
try:
    yhat_files = list(DIAG.glob("*YHAT_STATS.csv"))
    all_yhat = []
    for f in yhat_files:
        d = pd.read_csv(f)
        name = f.stem.replace("mcaware_","").replace("_YHAT_STATS","")
        d["model"] = name
        all_yhat.append(d)
    yhat = pd.concat(all_yhat, ignore_index=True)

    if "test_mean" in yhat.columns:
        models = yhat["model"].unique()[:8]
        data = [yhat[yhat["model"]==m]["test_mean"].dropna().values for m in models]
        data = [d for d in data if len(d) > 0]
        models = [m for m, d in zip(models, [yhat[yhat["model"]==mm]["test_mean"].dropna().values for mm in models]) if len(d) > 0]

        fig, ax = plt.subplots(figsize=(12, 5))
        vp = ax.violinplot(data, showmeans=True, showextrema=True)
        for i, body in enumerate(vp["bodies"]):
            body.set_facecolor([RED, GREEN, CYAN, ORANGE, PURPLE, YELLOW, PINK, "#66BB6A"][i % 8])
            body.set_alpha(0.7)
        vp["cmeans"].set_color("white")
        vp["cmaxes"].set_color("#666")
        vp["cmins"].set_color("#666")
        vp["cbars"].set_color("#666")
        ax.axhline(0.5, color=ORANGE, ls="--", alpha=0.5, label="Dengeli (0.5)")
        ax.set_xticks(range(1, len(models)+1))
        ax.set_xticklabels([m.replace("BiLSTM_","BL_").replace("multi_arch_","") for m in models], fontsize=8, rotation=25, ha="right")
        ax.set_ylabel("ŷ Test Ortalaması")
        ax.set_title("YHAT Test Dağılımı (Model Çıkış Ortalamaları)", fontsize=13, fontweight="bold", color=PURPLE)
        ax.legend(fontsize=9, framealpha=0.3)
        ax.grid(axis="y", alpha=0.3)
        save(fig, "52_YHAT_Violin_MultiModel.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 53. Voting Score → Accuracy Eğrisi
# ===================================================================
print("[53] Voting Score → Accuracy...")
try:
    vs = pd.read_csv(SUM / "mcaware_voting_score_meta_RESULTS.csv")
    if "voting_score" in vs.columns and "actual" in vs.columns:
        bins = sorted(vs["voting_score"].unique())
        acc_data = []
        for b in bins:
            sub = vs[vs["voting_score"] == b]
            majority = 1 if b > 0 else 0
            correct = (sub["actual"] == majority).sum()
            acc_data.append({"score": b, "n": len(sub), "acc": correct/len(sub) if len(sub) > 0 else 0})
        vdf = pd.DataFrame(acc_data)

        fig, ax1 = plt.subplots(figsize=(12, 5))
        ax2 = ax1.twinx()
        ax1.bar(vdf["score"], vdf["n"], color=CYAN, alpha=0.3, label="Örnek Sayısı")
        ax2.plot(vdf["score"], vdf["acc"], "o-", color=RED, linewidth=2.5, markersize=8, label="Doğruluk", zorder=5)
        ax2.axhline(0.5, color=ORANGE, ls="--", alpha=0.5)
        ax1.set_xlabel("Voting Score", fontsize=12)
        ax1.set_ylabel("Örnek Sayısı", fontsize=11, color=CYAN)
        ax2.set_ylabel("Doğruluk", fontsize=11, color=RED)
        ax1.set_title("Voting Score: Konsensüs Arttıkça Doğruluk Artmıyor!", fontsize=13, fontweight="bold", color=RED)
        lines1, labels1 = ax1.get_legend_handles_labels()
        lines2, labels2 = ax2.get_legend_handles_labels()
        ax1.legend(lines1+lines2, labels1+labels2, fontsize=9, framealpha=0.3)
        ax1.grid(axis="y", alpha=0.2)
        save(fig, "53_VotingScore_Accuracy.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 54. BiLSTM Evrim Çizgisi (v1 → attn_v6)
# ===================================================================
print("[54] BiLSTM Evrim Çizgisi...")
try:
    versions = [
        ("v1", "mcaware_prototype_BiLSTM_v1_SUMMARY.csv"),
        ("v2a", "mcaware_BiLSTM_v2a_SUMMARY.csv"),
        ("v2b", "mcaware_BiLSTM_v2b_SUMMARY.csv"),
        ("v2bfix", "mcaware_BiLSTM_v2bfix_SUMMARY.csv"),
        ("v3b", "mcaware_BiLSTM_v3b_SUMMARY.csv"),
        ("v3c_noCW", "mcaware_BiLSTM_v3c_no_cw_SUMMARY.csv"),
        ("attn_v6", "mcaware_BiLSTM_attn_v6_SUMMARY.csv"),
    ]
    evol = []
    for vname, fname in versions:
        f = SUM / fname
        if f.exists():
            d = pd.read_csv(f)
            if "mean_acc" in d.columns:
                evol.append({"version": vname, "acc": d["mean_acc"].mean(), "flip": d["mean_flip"].mean() if "mean_flip" in d.columns else 1-d["mean_acc"].mean()})
            elif "Acc_05" in d.columns:
                evol.append({"version": vname, "acc": d["Acc_05"].mean(), "flip": d["Acc_flip_05"].mean() if "Acc_flip_05" in d.columns else 1-d["Acc_05"].mean()})

    if evol:
        ev = pd.DataFrame(evol)
        fig, ax = plt.subplots(figsize=(12, 5))
        ax.plot(ev["version"], ev["acc"], "o-", color=RED, linewidth=2.5, markersize=12, label="Model Acc", zorder=5)
        ax.plot(ev["version"], ev["flip"], "s-", color=GREEN, linewidth=2.5, markersize=12, label="Flip Acc", zorder=5)
        ax.axhline(0.5, color="white", ls="--", alpha=0.4)
        ax.fill_between(range(len(ev)), ev["acc"], ev["flip"], alpha=0.1, color=GREEN)
        ax.set_ylabel("Doğruluk")
        ax.set_title("BiLSTM Evrim Çizgisi: v1 → v2a → v2b → v3b → v3c → attn_v6", fontsize=13, fontweight="bold", color=PURPLE)
        ax.legend(fontsize=10, framealpha=0.3)
        ax.grid(alpha=0.3)
        for i, r in enumerate(ev.itertuples()):
            ax.annotate(f"{r.acc:.3f}", (i, r.acc-0.015), ha="center", fontsize=8, color=RED)
            ax.annotate(f"{r.flip:.3f}", (i, r.flip+0.008), ha="center", fontsize=8, color=GREEN)
        save(fig, "54_BiLSTM_Evrim_Cizgisi.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 55. BES 3 Fon Karşılaştırma
# ===================================================================
print("[55] BES 3 Fon Detay...")
try:
    funds = []
    for fund in ["ALZ", "AMZ", "AZS"]:
        f = SUM / f"mcaware_BiLSTM_v3b_BES_{fund}_SUMMARY.csv"
        if f.exists():
            d = pd.read_csv(f)
            for _, r in d.iterrows():
                funds.append({"fund": fund, "lambda": r["lambda"], "acc": r["Acc_05"],
                              "flip": r["Acc_flip_05"], "naive": r["naive_acc"], "mc": r["MC_05"]})
    fdf = pd.DataFrame(funds)

    fig, axes = plt.subplots(1, 3, figsize=(15, 5), sharey=True)
    for ax, fund in zip(axes, ["ALZ", "AMZ", "AZS"]):
        sub = fdf[fdf["fund"] == fund]
        x = np.arange(len(sub))
        w = 0.25
        ax.bar(x-w, sub["acc"], w, label="Model", color=RED)
        ax.bar(x, sub["flip"], w, label="Flip", color=GREEN)
        ax.bar(x+w, sub["naive"], w, label="Naive", color=ORANGE)
        ax.axhline(0.5, color="white", ls="--", alpha=0.4)
        ax.set_xticks(x)
        ax.set_xticklabels([f"λ={l}" for l in sub["lambda"]], fontsize=9)
        ax.set_title(f"BES {fund}", fontsize=12, fontweight="bold", color=CYAN)
        ax.legend(fontsize=7, framealpha=0.3)
        ax.grid(axis="y", alpha=0.3)
        # MC trap annotation
        for i, r in enumerate(sub.itertuples()):
            if r.mc > 0:
                ax.text(i, 0.35, f"MC={int(r.mc)}", ha="center", fontsize=8, color=YELLOW, fontweight="bold")
    axes[0].set_ylabel("Doğruluk")
    fig.suptitle("BES Fonları: ALZ (MC Tuzağı!) vs AMZ vs AZS", fontsize=14, fontweight="bold", color=RED)
    fig.tight_layout()
    save(fig, "55_BES_3Fon_Detay.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 56. Threshold Multi-Arch Overlay
# ===================================================================
print("[56] Threshold Multi-Arch Overlay...")
try:
    arch_colors = {"BiLSTM_v3THYAO": RED, "Conv1D": GREEN, "GRU": CYAN, "SimpleRNN": ORANGE,
                   "TCN": PURPLE, "Transformer": YELLOW}
    fig, ax = plt.subplots(figsize=(12, 5))
    for arch_name, color in arch_colors.items():
        fname = f"mcaware_{arch_name}_THRESHOLD_GRID.csv" if "BiLSTM" in arch_name else f"mcaware_multi_arch_{arch_name}_THRESHOLD_GRID.csv"
        f = THR / fname
        if f.exists():
            d = pd.read_csv(f)
            avg = d.groupby("threshold")["Acc_test"].mean().reset_index()
            label = arch_name.replace("BiLSTM_v3THYAO", "BiLSTM").replace("multi_arch_", "")
            ax.plot(avg["threshold"], avg["Acc_test"], "o-", color=color, label=label, linewidth=2, markersize=5)

    ax.axhline(0.5, color="white", ls="--", alpha=0.4, label="Şans (%50)")
    ax.set_xlabel("Threshold (Eşik)", fontsize=12)
    ax.set_ylabel("Test Accuracy", fontsize=12)
    ax.set_title("Threshold Eğrisi: Tüm Mimariler Üst Üste", fontsize=13, fontweight="bold", color=RED)
    ax.legend(fontsize=9, framealpha=0.3, ncol=2)
    ax.grid(alpha=0.3)
    save(fig, "56_Threshold_MultiArch_Overlay.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 57. Seed Varyansı Box Plot (21 hisse)
# ===================================================================
print("[57] Seed Varyansı Box Plot...")
try:
    macro = pd.read_csv(SUM / "mcaware_bist_ALL_macro_SUMMARY.csv")
    sig_sv = pd.read_csv(DIAG / "mcaware_bist5_sigorta_v2_SEED_VAR.csv")

    # macro'dan per-stock accuracy spread
    fig, ax = plt.subplots(figsize=(14, 5))
    tickers = macro["ticker"].str.replace(".IS", "").tolist()
    # Acc_05 ve naive arasındaki gap
    gaps = macro["Acc_flip_05"] - macro["naive"]
    colors = [GREEN if g > 0 else RED for g in gaps]

    ax.bar(tickers, gaps, color=colors, alpha=0.85, edgecolor="#333")
    ax.axhline(0, color="white", ls="-", alpha=0.5)
    ax.set_ylabel("Flip Acc − Naive Acc (Fark)", fontsize=12)
    ax.set_title("BIST-11: Anti-Prediktif Güç (Flip − Naive)", fontsize=14, fontweight="bold", color=RED)
    ax.grid(axis="y", alpha=0.3)

    for i, (tk, g) in enumerate(zip(tickers, gaps)):
        label_color = GREEN if g > 0 else RED
        ax.text(i, g + (0.003 if g >= 0 else -0.01), f"{g:+.3f}", ha="center", fontsize=9, color=label_color)

    plt.xticks(rotation=45, ha="right")
    save(fig, "57_AntiPrediktif_Guc_PerStock.png")
except Exception as e: print(f"  ✗ {e}")

# ===================================================================
# 58. Anti-Prediktif Yoğunluk Haritası (Ticker × Deney)
# ===================================================================
print("[58] Anti-Prediktif Yoğunluk Haritası...")
try:
    macro = pd.read_csv(SUM / "mcaware_bist_ALL_macro_SUMMARY.csv")
    sig = pd.read_csv(SUM / "mcaware_bist5_sigorta_v2_SUMMARY.csv")
    hld = pd.read_csv(SUM / "mcaware_bist5_holding_SUMMARY.csv")

    # Sektörel anti-prediktif sınıflandırma
    tickers, flip_rates, sectors = [], [], []
    for _, r in macro.iterrows():
        tk = r["ticker"].replace(".IS", "")
        tickers.append(tk)
        flip_rates.append(r["Acc_flip_05"])
        if tk in ["THYAO", "PGSUS"]: sectors.append("Havacılık")
        elif tk in ["HEKTS", "SASA"]: sectors.append("Kimya/Spek.")
        elif tk in ["KRDMD"]: sectors.append("Emtia")
        elif tk in ["ISCTR", "YKBNK"]: sectors.append("Bankacılık")
        elif tk in ["FROTO", "DOAS"]: sectors.append("Otomotiv")
        elif tk in ["TAVHL"]: sectors.append("Havalimanı")
        else: sectors.append("Diğer")
    for _, r in sig.iterrows():
        tickers.append(r["ticker"].replace(".IS", ""))
        flip_rates.append(r["mean_flip"])
        sectors.append("Sigorta")
    for _, r in hld.iterrows():
        tickers.append(r["ticker"].replace(".IS", ""))
        flip_rates.append(r["mean_flip"])
        sectors.append("Holding")

    # Sektöre göre sırala
    df = pd.DataFrame({"ticker": tickers, "flip": flip_rates, "sector": sectors})
    df = df.sort_values(["sector", "flip"], ascending=[True, False])

    fig, ax = plt.subplots(figsize=(14, 6))
    colors_map = {"Havacılık": RED, "Kimya/Spek.": PINK, "Emtia": ORANGE, "Sigorta": PURPLE,
                  "Bankacılık": CYAN, "Otomotiv": GREEN, "Havalimanı": YELLOW, "Holding": "#66BB6A", "Diğer": "#888"}
    bar_colors = [colors_map.get(s, "#888") for s in df["sector"]]

    bars = ax.barh(range(len(df)), df["flip"], color=bar_colors, alpha=0.85, edgecolor="#333")
    ax.axvline(0.5, color="white", ls="--", alpha=0.5, label="Şans (%50)")
    ax.set_yticks(range(len(df)))
    ax.set_yticklabels(df["ticker"], fontsize=10)
    ax.set_xlabel("Flip Accuracy")
    ax.set_title("21 BIST Hissesi: Sektörel Anti-Prediktif Yoğunluk", fontsize=14, fontweight="bold", color=RED)
    ax.invert_yaxis()
    ax.grid(axis="x", alpha=0.3)

    # Legend
    patches = [mpatches.Patch(color=c, label=s) for s, c in colors_map.items() if s in df["sector"].values]
    ax.legend(handles=patches, fontsize=8, framealpha=0.3, loc="lower right")

    for i, (_, r) in enumerate(df.iterrows()):
        ax.text(r["flip"]+0.003, i, f"{r['flip']:.3f}", va="center", fontsize=8, color="#ddd")

    save(fig, "58_Sektorel_Yogunluk_Haritasi.png")
except Exception as e: print(f"  ✗ {e}")

print(f"\n{'='*60}")
print(f"10 yeni görsel üretildi → {OUT}")
print(f"Toplam görsel sayısı: {len(list(OUT.glob('*.png')))}")
print(f"{'='*60}")

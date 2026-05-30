"""
MC-AWARE  —  TÜBİTAK 2209-A Research Dashboard
Anti-Prediktif Davranışın Derin Öğrenme ile Tespiti
Researcher: Mehmet Ali Kurt  |  Advisor: Dr. Övgücan Karadağ Erdemir
Hacettepe Üniversitesi — Aktüerya Bilimleri
"""

import os, warnings, datetime, base64, io
from pathlib import Path
import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots

warnings.filterwarnings("ignore")

# ─── language dictionary ─────────────────────────────────────────────────────
TEXTS = {
    "title":           {"TR": "MC-AWARE Araştırma Paneli", "EN": "MC-AWARE Research Dashboard"},
    "subtitle":        {"TR": "TÜBİTAK 2209-A · Anti-Prediktif Davranışın Derin Öğrenme ile Tespiti · 2026",
                        "EN": "TÜBİTAK 2209-A · Detecting Anti-Predictive Behavior with Deep Learning · 2026"},
    "tab_main":        {"TR": "📊 Ana Bulgular",        "EN": "📊 Main Findings"},
    "tab_arch":        {"TR": "🏗️ Mimari Karşılaştırma", "EN": "🏗️ Architecture Comparison"},
    "tab_wf":          {"TR": "📈 Walk-Forward",        "EN": "📈 Walk-Forward"},
    "tab_evol":        {"TR": "🔬 BiLSTM Evrim",        "EN": "🔬 BiLSTM Evolution"},
    "tab_pred":        {"TR": "🔍 Tahmin Analizi",      "EN": "🔍 Prediction Analysis"},
    "tab_abl":         {"TR": "🧪 Ablation",            "EN": "🧪 Ablation"},
    "tab_cross":       {"TR": "🌍 Cross-Market",        "EN": "🌍 Cross-Market"},
    "tab_ens":         {"TR": "🗳️ Ensemble & Baseline", "EN": "🗳️ Ensemble & Baseline"},
    "tab_stat":        {"TR": "📐 İstatistiksel Kanıtlar", "EN": "📐 Statistical Evidence"},
    "tab_diag":        {"TR": "📊 Threshold & Diagnostics", "EN": "📊 Threshold & Diagnostics"},
    "total_config":    {"TR": "Toplam Konfigürasyon",   "EN": "Total Configurations"},
    "mc_trap":         {"TR": "MC Tuzağı",              "EN": "MC Trap"},
    "flip_naive":      {"TR": "Flip > Naive",           "EN": "Flip > Naive"},
    "anti_pred_rate":  {"TR": "Anti-Prediktif Oran",    "EN": "Anti-Predictive Rate"},
    "finding_main":    {"TR": "Model %41.8 doğrulukla çalıştığında, tahminleri ters çevirince (flip) %58.2'ye ulaşılıyor. "
                              "105 konfigürasyonun 103'ünde flip stratejisi naive'i geçiyor. "
                              "Bu, rastgele olma olasılığı p ≈ 3×10⁻¹⁴ olan sistematik anti-prediktif bir davranıştır.",
                        "EN": "When the model runs at 41.8% accuracy, flipping predictions reaches 58.2%. "
                              "In 103 out of 105 configurations, the flip strategy beats naive. "
                              "This is a systematic anti-predictive behavior with p ≈ 3×10⁻¹⁴."},
    "pooled_cm":       {"TR": "Havuzlanmış Confusion Matrix (7-fold)", "EN": "Pooled Confusion Matrix (7-fold)"},
    "pool_metrics":    {"TR": "Havuz Metrikleri",       "EN": "Pool Metrics"},
    "fold_cm":         {"TR": "Fold Bazlı Confusion Metrikleri", "EN": "Per-Fold Confusion Metrics"},
    "fold_metrics":    {"TR": "Fold Bazlı Metrikler",   "EN": "Per-Fold Metrics"},
    "arch_title":      {"TR": "Mimari Karşılaştırma (7 Mimari)", "EN": "Architecture Comparison (7 Architectures)"},
    "arch_chart":      {"TR": "7 Mimari: Model vs Flip vs Naive", "EN": "7 Architectures: Model vs Flip vs Naive"},
    "mcnemar_title":   {"TR": "McNemar Testi — Mimariler Arası İstatistiksel Fark", "EN": "McNemar Test — Statistical Difference Between Architectures"},
    "wf_heatmap":      {"TR": "Walk-Forward Multi-Arch Isı Haritası (Acc_flip)", "EN": "Walk-Forward Multi-Arch Heatmap (Acc_flip)"},
    "wf_title":        {"TR": "Walk-Forward Validation (7 Fold)", "EN": "Walk-Forward Validation (7 Folds)"},
    "wf_chart":        {"TR": "Walk-Forward 7-Fold: Doğruluk Evrimi", "EN": "Walk-Forward 7-Fold: Accuracy Evolution"},
    "fold_detail":     {"TR": "Fold Detay Tablosu",     "EN": "Fold Detail Table"},
    "evol_title":      {"TR": "BiLSTM Evrim: v1 → v2a → v2b → v2bfix → v3 → v3b → v3c → window → attn_v6",
                        "EN": "BiLSTM Evolution: v1 → v2a → v2b → v2bfix → v3 → v3b → v3c → window → attn_v6"},
    "evol_table":      {"TR": "Versiyon Karşılaştırma Tablosu (λ=0)", "EN": "Version Comparison Table (λ=0)"},
    "evol_chart":      {"TR": "BiLSTM Evrim: Model Acc vs Flip Acc (λ=0)", "EN": "BiLSTM Evolution: Model Acc vs Flip Acc (λ=0)"},
    "pred_title":      {"TR": "Tahmin Analizi",         "EN": "Prediction Analysis"},
    "pred_select":     {"TR": "Varlık / Mimari Seçin",  "EN": "Select Asset / Architecture"},
    "yhat_dist":       {"TR": "ŷ (yhat) Dağılımı",      "EN": "ŷ (yhat) Distribution"},
    "cum_acc":         {"TR": "Kümülatif Doğruluk",     "EN": "Cumulative Accuracy"},
    "bes_cross":       {"TR": "BES Çapraz-Fon Özeti",   "EN": "BES Cross-Fund Summary"},
    "abl_title":       {"TR": "Ablation Çalışmaları",   "EN": "Ablation Studies"},
    "feat_group":      {"TR": "Özellik Grubu Ablasyonu (full_13 vs no_ext_10)", "EN": "Feature Group Ablation (full_13 vs no_ext_10)"},
    "single_feat":     {"TR": "Tekli Özellik Ablasyonu", "EN": "Single Feature Ablation"},
    "cross_title":     {"TR": "Cross-Market & Multi-Stock", "EN": "Cross-Market & Multi-Stock"},
    "ens_title":       {"TR": "Ensemble & Baseline",    "EN": "Ensemble & Baseline"},
    "stat_title":      {"TR": "İstatistiksel Kanıtlar",  "EN": "Statistical Evidence"},
    "diag_title":      {"TR": "Threshold & Diagnostics", "EN": "Threshold & Diagnostics"},
    "sidebar_project": {"TR": "Proje", "EN": "Project"},
    "sidebar_researcher": {"TR": "Araştırmacı", "EN": "Researcher"},
    "sidebar_advisor": {"TR": "Danışman", "EN": "Advisor"},
    "sidebar_uni":     {"TR": "Üniversite", "EN": "University"},
    "sidebar_arch":    {"TR": "Mimariler", "EN": "Architectures"},
    "sidebar_data":    {"TR": "Veri Kaynakları", "EN": "Data Sources"},
    "sidebar_exp":     {"TR": "Deney Serileri", "EN": "Experiment Series"},
    "sidebar_csv":     {"TR": "Toplam CSV", "EN": "Total CSV"},
    "sidebar_config":  {"TR": "Toplam Konfigürasyon", "EN": "Total Configurations"},
    "sidebar_note":    {"TR": "Tüm veriler gerçek deneylerden elde edilmiştir.", "EN": "All data obtained from real experiments."},
    "pdf_btn":         {"TR": "📄 PDF Rapor İndir", "EN": "📄 Download PDF Report"},
    "lang_label":      {"TR": "🌐 Dil / Language", "EN": "🌐 Language / Dil"},
}

# ─── paths ───────────────────────────────────────────────────────────────────
BASE = Path(os.path.dirname(os.path.abspath(__file__)))
DIRS = {
    "summaries":   BASE / "Sonuclar" / "summaries",
    "predictions": BASE / "Sonuclar" / "predictions",
    "diagnostics": BASE / "Sonuclar" / "diagnostics",
    "thresholds":  BASE / "Sonuclar" / "thresholds",
}

# ─── helpers ─────────────────────────────────────────────────────────────────
@st.cache_data
def L(folder: str, name: str):
    """Load a CSV from the given folder. Returns None on failure."""
    p = DIRS[folder] / name
    try:
        return pd.read_csv(p)
    except Exception:
        return None

PD_TEMPLATE = "plotly_dark"
TRANSPARENT = "rgba(0,0,0,0)"

def _layout(fig, **kw):
    fig.update_layout(
        template=PD_TEMPLATE,
        paper_bgcolor=TRANSPARENT,
        plot_bgcolor=TRANSPARENT,
        **kw,
    )
    return fig

def metric_card(label, value, color="#00FF00"):
    st.markdown(
        f"""<div style="background:#1E1E1E;border:1px solid #333;border-radius:10px;
        padding:18px 16px;text-align:center;">
        <div style="font-size:0.85rem;color:#aaa;">{label}</div>
        <div style="font-size:1.8rem;font-weight:700;color:{color};">{value}</div>
        </div>""",
        unsafe_allow_html=True,
    )

def finding_box(text, title="🔬 Temel Bulgu"):
    st.markdown(
        f"""<div style="background:linear-gradient(135deg,#1a1a2e,#16213e);
        border-left:4px solid #FF416C;border-radius:8px;padding:16px 20px;
        margin:12px 0;">
        <div style="font-weight:700;color:#FF416C;margin-bottom:6px;">{title}</div>
        <div style="color:#ddd;font-size:0.92rem;">{text}</div>
        </div>""",
        unsafe_allow_html=True,
    )

def section(text):
    st.markdown(f"### {text}")

def t(key):
    """Return translated text for current language."""
    lang = st.session_state.get("lang", "TR")
    entry = TEXTS.get(key)
    if entry is None:
        return key
    return entry.get(lang, entry.get("TR", key))

def generate_pdf_html():
    """Generate a downloadable HTML report summarizing key findings."""
    lang = st.session_state.get("lang", "TR")
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    title = t("title")
    # Load key data
    arch = L("summaries", "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv")
    wf = L("summaries", "mcaware_walkforward_RESULTS.csv")
    fa = L("summaries", "mcaware_feature_ablation_SUMMARY.csv")
    nq = L("summaries", "mcaware_nasdaq_SUMMARY.csv")
    ens = L("summaries", "mcaware_ensemble_RESULTS.csv")

    arch_rows = ""
    if arch is not None:
        for _, r in arch.iterrows():
            arch_rows += f"<tr><td>{r['arch']}</td><td>{r['mean_acc']:.4f}</td><td>{r['mean_acc_flip']:.4f}</td><td>{r['naive_acc']:.4f}</td></tr>"
    wf_rows = ""
    if wf is not None:
        for _, r in wf.iterrows():
            wf_rows += f"<tr><td>{int(r['fold'])}</td><td>{r['acc']:.4f}</td><td>{r['acc_flip']:.4f}</td><td>{r['naive_acc']:.4f}</td></tr>"

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{title}</title>
<style>
body {{ font-family: 'Segoe UI', Arial, sans-serif; max-width: 900px; margin: 40px auto; color: #222; line-height: 1.6; }}
h1 {{ color: #FF416C; border-bottom: 3px solid #FF416C; padding-bottom: 10px; }}
h2 {{ color: #1B3A5C; margin-top: 30px; }}
table {{ border-collapse: collapse; width: 100%; margin: 15px 0; }}
th {{ background: #1B3A5C; color: white; padding: 10px; text-align: center; }}
td {{ border: 1px solid #ddd; padding: 8px; text-align: center; }}
tr:nth-child(even) {{ background: #f8f9fa; }}
.badge {{ display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 0.85rem; font-weight: 600; margin: 2px; }}
.red {{ background: #FFE0E0; color: #CC0000; }}
.green {{ background: #E0FFE0; color: #008800; }}
.footer {{ margin-top: 40px; padding-top: 15px; border-top: 1px solid #ddd; color: #888; font-size: 0.85rem; text-align: center; }}
</style></head><body>
<h1>🔬 {title}</h1>
<p><strong>TÜBİTAK 2209-A</strong> · Mehmet Ali Kurt · Dr. Övgücan Karadağ Erdemir · Hacettepe Üniversitesi</p>
<p><em>{"Rapor tarihi" if lang=="TR" else "Report date"}: {now}</em></p>

<h2>{"Ana Bulgular" if lang=="TR" else "Main Findings"}</h2>
<p><span class="badge red">{"Anti-Prediktif Oran" if lang=="TR" else "Anti-Predictive Rate"}: %98</span>
<span class="badge green">MC {"Tuzağı" if lang=="TR" else "Trap"}: 0/105</span>
<span class="badge red">p ≈ 3×10⁻¹⁴</span></p>
<p>{t("finding_main")}</p>

<h2>{"Mimari Karşılaştırma" if lang=="TR" else "Architecture Comparison"}</h2>
<table><tr><th>{"Mimari" if lang=="TR" else "Architecture"}</th><th>Model Acc</th><th>Flip Acc</th><th>Naive</th></tr>{arch_rows}</table>

<h2>Walk-Forward (7 Fold)</h2>
<table><tr><th>Fold</th><th>Model Acc</th><th>Flip Acc</th><th>Naive</th></tr>{wf_rows}</table>

<div class="footer">
<p>MC-AWARE · TÜBİTAK 2209-A · 2026 · {"Tüm veriler gerçek deneylerden elde edilmiştir." if lang=="TR" else "All data from real experiments."}</p>
</div>
</body></html>"""
    return html

# ─── page config ─────────────────────────────────────────────────────────────
st.set_page_config(page_title="MC-AWARE Dashboard", page_icon="🔬", layout="wide")

st.markdown("""
<style>
    .stTabs [data-baseweb="tab-list"] { gap: 2px; }
    .stTabs [data-baseweb="tab"] {
        padding: 8px 16px; border-radius: 6px 6px 0 0;
        font-size: 0.82rem;
    }
    section[data-testid="stSidebar"] { background: #0E1117; }
</style>
""", unsafe_allow_html=True)

# ─── title ───────────────────────────────────────────────────────────────────
st.markdown(
    f"""<h1 style="text-align:center;background:linear-gradient(90deg,#FF4B2B,#FF416C);
    -webkit-background-clip:text;-webkit-text-fill-color:transparent;
    font-size:2.3rem;margin-bottom:0;">{t('title')}</h1>
    <p style="text-align:center;color:#888;margin-top:0;">
    {t('subtitle')}</p>""",
    unsafe_allow_html=True,
)

# ─── sidebar ─────────────────────────────────────────────────────────────────
with st.sidebar:
    # Language selector (top of sidebar)
    lang_choice = st.selectbox(t("lang_label"), ["Türkçe", "English"], index=0, key="lang_select")
    st.session_state["lang"] = "TR" if lang_choice == "Türkçe" else "EN"

    st.divider()
    st.markdown("## 🔬 MC-AWARE")
    st.markdown(f"""
    **{t('sidebar_project')}:** TÜBİTAK 2209-A (2026)

    **{t('sidebar_researcher')}:** Mehmet Ali Kurt
    **{t('sidebar_advisor')}:** Dr. Övgücan Karadağ Erdemir
    **{t('sidebar_uni')}:** Hacettepe — Aktüerya Bilimleri
    """)
    st.divider()
    st.markdown(f"#### 🏗️ {t('sidebar_arch')}")
    for a in ["BiLSTM", "GRU", "SimpleRNN", "Conv1D", "TCN", "Transformer"]:
        st.markdown(f"- {a}")
    st.divider()
    st.markdown(f"#### 📊 {t('sidebar_data')}")
    st.markdown("- BIST (THYAO, GARAN, …)")
    st.markdown("- NASDAQ (AAPL)")
    st.markdown("- BES (AMZ, AZS, ALZ)")
    st.divider()
    st.markdown(f"#### 🧪 {t('sidebar_exp')}")
    experiments = [
        "BiLSTM v1-v3", "Multi-Arch (7)", "Walk-Forward (7-fold)",
        "Feature Ablation", "Single-Feat Ablation", "Input-Length Ablation",
        "Cross-Market (NASDAQ)", "Multi-Stock (BIST-3/5)",
        "Ensemble (Hard+Soft)", "Rule-Based Baseline", "Threshold Grid",
    ]
    for e in experiments:
        st.markdown(f"- {e}")
    st.divider()
    st.markdown(f"**{t('sidebar_csv')}:** 120")
    st.markdown(f"**{t('sidebar_config')}:** 350+")
    st.caption(t("sidebar_note"))

    # PDF Download
    st.divider()
    pdf_html = generate_pdf_html()
    st.download_button(
        label=t("pdf_btn"),
        data=pdf_html.encode("utf-8"),
        file_name=f"MC-AWARE_Report_{datetime.datetime.now().strftime('%Y%m%d')}.html",
        mime="text/html",
        use_container_width=True,
    )

# ─── tabs ────────────────────────────────────────────────────────────────────
tabs = st.tabs([
    t("tab_main"), t("tab_arch"), t("tab_wf"), t("tab_evol"),
    t("tab_pred"), t("tab_abl"), t("tab_cross"), t("tab_ens"),
    t("tab_stat"), t("tab_diag"), "⚔️ Karşılaştırma",
])

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 1 — Ana Bulgular                                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[0]:
    section(t("tab_main").replace("📊 ", ""))

    # ── Hero metrics with st.metric ──
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        st.metric("🧪 Toplam Konfigürasyon", "105", help="6 mimari × çoklu lambda/seed")
    with c2:
        st.metric("🪤 MC Tuzağı", "0 / 105", delta="Sıfır!", delta_color="normal",
                  help="Hiçbir model majority class'a sıkışmadı")
    with c3:
        st.metric("🔄 Flip > Naive", "103 / 105", delta="%98 oran",
                  help="Tahminleri ters çevirince naive'den iyi")
    with c4:
        st.metric("📉 Model Doğruluğu", "%41.8", delta="-8.2%", delta_color="inverse",
                  help="Model şanstan kötü → anti-prediktif")

    # ── Narrative story box ──
    st.markdown("""
    <div style="background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
                border-left: 5px solid #FF416C; border-radius: 10px; padding: 25px; margin: 20px 0;">
        <h3 style="color: #FF416C; margin-top: 0;">🔬 Ne Bulduk?</h3>
        <p style="color: #ddd; font-size: 1.1rem; line-height: 1.8;">
            <b>6 farklı derin öğrenme mimarisi</b> (BiLSTM, GRU, Conv1D, TCN, Transformer, SimpleRNN) ile
            <b>105 farklı konfigürasyon</b> test ettik. Sonuç şaşırtıcı:
        </p>
        <div style="display: flex; justify-content: center; gap: 30px; margin: 20px 0;">
            <div style="text-align: center;">
                <div style="font-size: 2.5rem; font-weight: 800; color: #FF4444;">%41.8</div>
                <div style="color: #aaa;">Model Doğruluğu</div>
            </div>
            <div style="text-align: center; font-size: 2rem; color: #666; padding-top: 15px;">→ flip →</div>
            <div style="text-align: center;">
                <div style="font-size: 2.5rem; font-weight: 800; color: #00FF00;">%58.2</div>
                <div style="color: #aaa;">Flip Doğruluğu</div>
            </div>
        </div>
        <p style="color: #ccc; font-size: 1rem;">
            Model <b>sistematik olarak yanlış</b> tahmin yapıyor. Tahminleri ters çevirince
            naive stratejiden bile iyi sonuç alınıyor. Bu <b>anti-prediktif davranış</b>,
            p ≈ 3×10⁻¹⁴ ile istatistiksel olarak anlamlı.
        </p>
    </div>
    """, unsafe_allow_html=True)

    # ── Anti-predictive rate progress bar ──
    st.markdown("#### 📊 Anti-Prediktif Oran")
    pcol1, pcol2 = st.columns([3, 1])
    with pcol1:
        st.progress(103/105, text="103 / 105 konfigürasyonda flip > naive")
    with pcol2:
        st.markdown(f"<div style='text-align:center; font-size:2rem; font-weight:800; color:#FF416C;'>%98</div>",
                    unsafe_allow_html=True)

    # Pooled confusion matrix
    st.markdown("---")
    col_cm, col_met = st.columns([1, 1])

    df_cm = L("summaries", "mcaware_pooled_confusion_matrix.csv")
    if df_cm is not None:
        with col_cm:
            st.markdown(f"#### {t('pooled_cm')}")
            metrics_dict = dict(zip(df_cm["metric"], df_cm["value"]))
            tp = int(metrics_dict.get("TP", 0))
            fp = int(metrics_dict.get("FP", 0))
            fn = int(metrics_dict.get("FN", 0))
            tn = int(metrics_dict.get("TN", 0))
            cm = np.array([[tn, fp], [fn, tp]])
            fig = px.imshow(
                cm,
                labels=dict(x="Tahmin", y="Gerçek", color="Sayı"),
                x=["Down (0)", "Up (1)"],
                y=["Down (0)", "Up (1)"],
                text_auto=True,
                color_continuous_scale="RdYlGn",
            )
            _layout(fig, title="Pooled Confusion Matrix", height=380)
            st.plotly_chart(fig, use_container_width=True)

        with col_met:
            st.markdown(f"#### {t('pool_metrics')}")
            met_df = df_cm.copy()
            met_df.columns = ["Metrik", "Değer"]
            met_df["Değer"] = met_df["Değer"].apply(
                lambda v: f"{v:.4f}" if isinstance(v, float) else str(v)
            )
            st.dataframe(met_df, use_container_width=True, hide_index=True)

    # Per-fold confusion
    df_fold = L("summaries", "mcaware_pooled_confusion_by_fold.csv")
    if df_fold is not None:
        st.markdown("#### Fold Bazlı Confusion Metrikleri")
        st.dataframe(df_fold.style.format({
            c: "{:.3f}" for c in df_fold.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

        fig = go.Figure()
        fig.add_trace(go.Bar(x=df_fold["fold"], y=df_fold["Acc"], name="Accuracy", marker_color="#FF416C"))
        fig.add_trace(go.Bar(x=df_fold["fold"], y=df_fold["Sens"], name="Sensitivity", marker_color="#00BFFF"))
        fig.add_trace(go.Bar(x=df_fold["fold"], y=df_fold["Spec"], name="Specificity", marker_color="#00FF00"))
        _layout(fig, title="Fold Bazlı Metrikler", barmode="group",
                xaxis_title="Fold", yaxis_title="Değer", height=380)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray",
                      annotation_text="Şans seviyesi (%50)", annotation_position="top right")
        st.plotly_chart(fig, use_container_width=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 2 — Mimari Karşılaştırma                                           ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[1]:
    section(t("arch_title"))

    df_arch = L("summaries", "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv")
    if df_arch is not None:
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_arch["arch"], y=df_arch["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_arch["arch"], y=df_arch["mean_acc_flip"], marker_color="#00FF00"))
        fig.add_trace(go.Bar(name="Naive Acc", x=df_arch["arch"], y=df_arch["naive_acc"], marker_color="#FFA500"))
        _layout(fig, barmode="group", title="7 Mimari: Model vs Flip vs Naive",
                xaxis_title="Mimari", yaxis_title="Doğruluk", height=450)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray", annotation_text="Şans (%50)")
        st.plotly_chart(fig, use_container_width=True)

        st.dataframe(df_arch.style.format({
            c: "{:.4f}" for c in df_arch.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # McNemar heatmap
    df_mcn = L("diagnostics", "mcaware_multi_arch_McNEMAR.csv")
    if df_mcn is not None:
        st.markdown("---")
        st.markdown("#### McNemar Testi — Mimariler Arası İstatistiksel Fark")

        archs_all = sorted(set(df_mcn["arch1"].tolist() + df_mcn["arch2"].tolist()))
        n = len(archs_all)
        mat = pd.DataFrame(np.nan, index=archs_all, columns=archs_all)
        for _, row in df_mcn.iterrows():
            pv = row["p_value"]
            mat.loc[row["arch1"], row["arch2"]] = pv
            mat.loc[row["arch2"], row["arch1"]] = pv
        for a in archs_all:
            mat.loc[a, a] = 1.0

        fig = px.imshow(
            mat.values.astype(float),
            x=archs_all, y=archs_all,
            text_auto=".3f",
            color_continuous_scale="RdYlGn",
            labels=dict(color="p-value"),
        )
        _layout(fig, title="McNemar p-value Matrisi (< 0.05 = Anlamlı fark)", height=450)
        st.plotly_chart(fig, use_container_width=True)

        st.dataframe(df_mcn.style.format({
            c: "{:.4f}" for c in df_mcn.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # Walk-Forward Multi-Arch heatmap
    df_wfma = L("summaries", "mcaware_walkforward_multi_arch_RESULTS.csv")
    if df_wfma is not None:
        st.markdown("---")
        st.markdown("#### Walk-Forward Multi-Arch Isı Haritası (Acc_flip)")
        pivot = df_wfma.pivot_table(index="arch", columns="fold", values="Acc_flip", aggfunc="first")
        fig = px.imshow(
            pivot.values,
            x=[f"Fold {c}" for c in pivot.columns],
            y=pivot.index.tolist(),
            text_auto=".3f",
            color_continuous_scale="RdYlGn",
            labels=dict(color="Acc_flip"),
        )
        _layout(fig, title="Mimari × Fold → Flip Accuracy", height=400)
        st.plotly_chart(fig, use_container_width=True)

    # Walk-Forward arch summary
    df_wfas = L("summaries", "mcaware_walkforward_multi_arch_ARCH_SUMMARY.csv")
    if df_wfas is not None:
        st.markdown("#### Walk-Forward Mimari Özeti")
        st.dataframe(df_wfas.style.format({
            c: "{:.4f}" for c in df_wfas.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 3 — Walk-Forward Validation                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[2]:
    section(t("wf_title"))

    df_wf = L("summaries", "mcaware_walkforward_RESULTS.csv")
    if df_wf is not None:
        fig = go.Figure()
        fig.add_trace(go.Scatter(x=df_wf["fold"], y=df_wf["acc"], mode="lines+markers",
                                 name="Model Acc", line=dict(color="#FF416C", width=3)))
        fig.add_trace(go.Scatter(x=df_wf["fold"], y=df_wf["acc_flip"], mode="lines+markers",
                                 name="Flip Acc", line=dict(color="#00FF00", width=3)))
        fig.add_trace(go.Scatter(x=df_wf["fold"], y=df_wf["naive_acc"], mode="lines+markers",
                                 name="Naive Acc", line=dict(color="#FFA500", width=2, dash="dash")))
        _layout(fig, title="Walk-Forward 7-Fold: Doğruluk Evrimi",
                xaxis_title="Fold", yaxis_title="Doğruluk", height=420)
        fig.add_hline(y=0.5, line_dash="dot", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)

        st.markdown("#### Fold Detay Tablosu")
        st.dataframe(df_wf.style.format({
            c: "{:.4f}" for c in df_wf.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # Fold summary from multi-arch
    df_fs = L("summaries", "mcaware_walkforward_multi_arch_FOLD_SUMMARY.csv")
    if df_fs is not None:
        st.markdown("---")
        st.markdown("#### Walk-Forward Fold Özeti (Tüm Mimariler)")
        st.dataframe(df_fs.style.format({
            c: "{:.4f}" for c in df_fs.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

        fig = go.Figure()
        fig.add_trace(go.Bar(x=df_fs["fold"], y=df_fs["mean_acc"], name="Mean Acc", marker_color="#FF416C"))
        fig.add_trace(go.Bar(x=df_fs["fold"], y=df_fs["mean_flip"], name="Mean Flip", marker_color="#00FF00"))
        fig.add_trace(go.Scatter(x=df_fs["fold"], y=df_fs["naive"], name="Naive",
                                 mode="lines+markers", line=dict(color="#FFA500", width=2, dash="dash")))
        _layout(fig, barmode="group", title="Fold Özeti: Ortalama Acc vs Flip vs Naive",
                xaxis_title="Fold", yaxis_title="Doğruluk", height=400)
        st.plotly_chart(fig, use_container_width=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 4 — BiLSTM Evrim                                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[3]:
    section(t("evol_title"))

    # Build combined evolution table
    versions = [
        ("v1",       "mcaware_BiLSTM_v1_SUMMARY.csv"),
        ("v2a",      "mcaware_BiLSTM_v2a_SUMMARY.csv"),
        ("v2b",      "mcaware_BiLSTM_v2b_SUMMARY.csv"),
        ("v2bfix",   "mcaware_BiLSTM_v2bfix_SUMMARY.csv"),
        ("v3_THYAO", "mcaware_BiLSTM_v3THYAO_SUMMARY.csv"),
        ("v3b_GARAN","mcaware_BiLSTM_v3b_GARAN_SUMMARY.csv"),
        ("v3c_noCW", "mcaware_BiLSTM_v3c_no_cw_SUMMARY.csv"),
        ("v3b_window","mcaware_BiLSTM_v3b_window_SUMMARY.csv"),
        ("attn_v6",  "mcaware_BiLSTM_attn_v6_SUMMARY.csv"),
    ]

    rows = []
    for vname, fname in versions:
        df = L("summaries", fname)
        if df is None:
            continue
        # Get lambda=0 row
        lam0 = df[df["lambda"] == 0]
        if lam0.empty:
            lam0 = df.iloc[:1]
        row = lam0.iloc[0]
        entry = {"Versiyon": vname}
        # Common columns — try various names
        for cand in ["Acc_05", "Acc_m"]:
            if cand in row.index:
                entry["Acc_05"] = row[cand]
                break
        for cand in ["Spec_05", "Spec_m"]:
            if cand in row.index:
                entry["Spec_05"] = row[cand]
                break
        for cand in ["Sens_05", "Sens_m"]:
            if cand in row.index:
                entry["Sens_05"] = row[cand]
                break
        if "Acc_flip_05" in row.index:
            entry["Flip_Acc"] = row["Acc_flip_05"]
        elif "Acc_05" in row.index:
            entry["Flip_Acc"] = 1 - row["Acc_05"]
        elif "Acc_m" in row.index:
            entry["Flip_Acc"] = 1 - row["Acc_m"]
        rows.append(entry)

    if rows:
        evo_df = pd.DataFrame(rows)
        st.markdown("#### Versiyon Karşılaştırma Tablosu (λ=0)")
        st.dataframe(evo_df.style.format({
            c: "{:.4f}" for c in evo_df.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

        # Bar chart
        fig = go.Figure()
        if "Acc_05" in evo_df.columns:
            fig.add_trace(go.Bar(name="Model Acc", x=evo_df["Versiyon"], y=evo_df["Acc_05"], marker_color="#FF416C"))
        if "Flip_Acc" in evo_df.columns:
            fig.add_trace(go.Bar(name="Flip Acc", x=evo_df["Versiyon"], y=evo_df["Flip_Acc"], marker_color="#00FF00"))
        _layout(fig, barmode="group", title="BiLSTM Evrim: Model Acc vs Flip Acc (λ=0)",
                xaxis_title="Versiyon", yaxis_title="Doğruluk", height=420)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)

    # Show individual summaries in expanders
    for vname, fname in versions:
        df = L("summaries", fname)
        if df is not None:
            with st.expander(f"📄 {vname} — Detay Tablosu"):
                st.dataframe(df.style.format({
                    c: "{:.4f}" for c in df.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)

    # OPTIMAL configurations
    st.markdown("---")
    st.markdown("#### 🏆 En İyi Konfigürasyonlar (OPTIMAL)")
    optimal_files = [
        ("v1",        "mcaware_BiLSTM_v1_RESULTS.csv"),
        ("v2a",       "mcaware_BiLSTM_v2a_OPTIMAL.csv"),
        ("v2b",       "mcaware_BiLSTM_v2b_OPTIMAL.csv"),
        ("v2bfix",    "mcaware_BiLSTM_v2bfix_OPTIMAL.csv"),
        ("v3_THYAO",  "mcaware_BiLSTM_v3THYAO_OPTIMAL.csv"),
        ("v3b_GARAN", "mcaware_BiLSTM_v3b_GARAN_OPTIMAL.csv"),
        ("v3b_window","mcaware_BiLSTM_v3b_window_OPTIMAL.csv"),
        ("v3c_noCW",  "mcaware_BiLSTM_v3c_no_cw_OPTIMAL.csv"),
        ("attn_v6",   "mcaware_BiLSTM_attn_v6_OPTIMAL.csv"),
        ("Conv1D",    "mcaware_multi_arch_Conv1D_OPTIMAL.csv"),
        ("GRU",       "mcaware_multi_arch_GRU_OPTIMAL.csv"),
        ("SimpleRNN", "mcaware_multi_arch_SimpleRNN_OPTIMAL.csv"),
        ("TCN",       "mcaware_multi_arch_TCN_OPTIMAL.csv"),
        ("Transformer","mcaware_multi_arch_Transformer_OPTIMAL.csv"),
    ]
    for oname, ofname in optimal_files:
        odf = L("summaries", ofname)
        if odf is not None:
            with st.expander(f"🏆 {oname} — Optimal Konfigürasyonlar"):
                st.dataframe(odf.style.format({
                    c: "{:.4f}" for c in odf.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 5 — Tahmin Analizi                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[4]:
    section(t("pred_title"))

    PRED_MAP = {
        "THYAO":       ("predictions", "mcaware_BiLSTM_v3THYAO_PREDICTIONS.csv",     "stock"),
        "GARAN":       ("predictions", "mcaware_BiLSTM_v3b_GARAN_PREDICTIONS.csv",   "stock"),
        "BES-AMZ":     ("predictions", "mcaware_BiLSTM_v3b_BES_AMZ_PREDICTIONS.csv", "bes"),
        "BES-AZS":     ("predictions", "mcaware_BiLSTM_v3b_BES_AZS_PREDICTIONS.csv", "bes"),
        "BES-ALZ":     ("predictions", "mcaware_BiLSTM_v3b_BES_ALZ_PREDICTIONS.csv", "bes"),
        "BiLSTM v2a":  ("predictions", "mcaware_BiLSTM_v2a_PREDICTIONS.csv",          "stock"),
        "BiLSTM v2b":  ("predictions", "mcaware_BiLSTM_v2b_PREDICTIONS.csv",          "stock"),
        "BiLSTM v2bfix":("predictions", "mcaware_BiLSTM_v2bfix_PREDICTIONS.csv",      "stock"),
        "BiLSTM window":("predictions", "mcaware_BiLSTM_v3b_window_PREDICTIONS.csv",  "stock"),
        "BiLSTM noCW": ("predictions", "mcaware_BiLSTM_v3c_no_cw_PREDICTIONS.csv",   "stock"),
        "BiLSTM attn": ("predictions", "mcaware_BiLSTM_attn_v6_PREDICTIONS.csv",     "stock"),
        "Conv1D":      ("predictions", "mcaware_multi_arch_Conv1D_PREDICTIONS.csv",      "arch"),
        "GRU":         ("predictions", "mcaware_multi_arch_GRU_PREDICTIONS.csv",          "arch"),
        "SimpleRNN":   ("predictions", "mcaware_multi_arch_SimpleRNN_PREDICTIONS.csv",    "arch"),
        "TCN":         ("predictions", "mcaware_multi_arch_TCN_PREDICTIONS.csv",          "arch"),
        "Transformer": ("predictions", "mcaware_multi_arch_Transformer_PREDICTIONS.csv",  "arch"),
    }

    sel_asset = st.selectbox("Varlık / Mimari Seçin", list(PRED_MAP.keys()))
    folder, fname, ptype = PRED_MAP[sel_asset]
    df_pred = L(folder, fname)

    if df_pred is not None:
        # Filter to test set
        if ptype == "stock" and "set" in df_pred.columns:
            df_pred = df_pred[df_pred["set"] == "test"].copy()
        elif ptype == "arch" and "set" in df_pred.columns:
            df_pred = df_pred[df_pred["set"] == "test"].copy()
        # BES: no set column, use all

        # Lambda & seed selectors
        col_l, col_s = st.columns(2)
        lambdas = sorted(df_pred["lambda"].unique()) if "lambda" in df_pred.columns else [0]
        seeds = sorted(df_pred["seed"].unique()) if "seed" in df_pred.columns else [0]
        with col_l:
            sel_lam = st.selectbox("Lambda", lambdas, key="pred_lam")
        with col_s:
            sel_seed = st.selectbox("Seed", seeds, key="pred_seed")

        mask = pd.Series(True, index=df_pred.index)
        if "lambda" in df_pred.columns:
            mask &= df_pred["lambda"] == sel_lam
        if "seed" in df_pred.columns:
            mask &= df_pred["seed"] == sel_seed
        dfs = df_pred[mask].copy()

        if len(dfs) > 0:
            dfs["pred"] = (dfs["yhat"] >= 0.5).astype(int)
            dfs["correct"] = (dfs["pred"] == dfs["y_true"]).astype(int)
            dfs["pred_flip"] = 1 - dfs["pred"]
            dfs["correct_flip"] = (dfs["pred_flip"] == dfs["y_true"]).astype(int)
            n_test = len(dfs)
            model_acc = dfs["correct"].mean()
            flip_acc = dfs["correct_flip"].mean()
            naive_acc = dfs["y_true"].mode().iloc[0]
            naive_acc_val = max(dfs["y_true"].mean(), 1 - dfs["y_true"].mean())

            mc1, mc2, mc3, mc4 = st.columns(4)
            with mc1: metric_card("Test N", str(n_test))
            with mc2: metric_card("Model Acc", f"{model_acc:.4f}", "#FF4444")
            with mc3: metric_card("Flip Acc", f"{flip_acc:.4f}", "#00FF00")
            with mc4: metric_card("Naive Acc", f"{naive_acc_val:.4f}", "#FFA500")

            # yhat histogram
            st.markdown("#### ŷ (yhat) Dağılımı")
            fig = px.histogram(dfs, x="yhat", color="y_true", nbins=40,
                               marginal="rug", barmode="overlay",
                               color_discrete_map={0: "#FF4444", 1: "#00FF00"},
                               labels={"yhat": "ŷ", "y_true": "Gerçek Sınıf"})
            fig.add_vline(x=0.5, line_dash="dash", line_color="white", annotation_text="Eşik=0.5")
            _layout(fig, title="ŷ Dağılımı (Gerçek Sınıfa Göre Renkli)", height=380)
            st.plotly_chart(fig, use_container_width=True)

            # Confusion matrix
            st.markdown("#### Confusion Matrix")
            tp = ((dfs["pred"] == 1) & (dfs["y_true"] == 1)).sum()
            fp = ((dfs["pred"] == 1) & (dfs["y_true"] == 0)).sum()
            fn = ((dfs["pred"] == 0) & (dfs["y_true"] == 1)).sum()
            tn = ((dfs["pred"] == 0) & (dfs["y_true"] == 0)).sum()
            cm = np.array([[tn, fp], [fn, tp]])
            fig = px.imshow(cm, x=["Pred 0", "Pred 1"], y=["True 0", "True 1"],
                            text_auto=True, color_continuous_scale="Blues")
            _layout(fig, title="Confusion Matrix", height=350)
            st.plotly_chart(fig, use_container_width=True)

            # Cumulative accuracy
            st.markdown("#### Kümülatif Doğruluk")
            dfs = dfs.reset_index(drop=True)
            dfs["cum_acc"] = dfs["correct"].expanding().mean()
            dfs["cum_flip"] = dfs["correct_flip"].expanding().mean()
            fig = go.Figure()
            fig.add_trace(go.Scatter(y=dfs["cum_acc"], mode="lines",
                                     name="Kümülatif Model Acc", line=dict(color="#FF416C")))
            fig.add_trace(go.Scatter(y=dfs["cum_flip"], mode="lines",
                                     name="Kümülatif Flip Acc", line=dict(color="#00FF00")))
            _layout(fig, title="Kümülatif Doğruluk Evrimi", xaxis_title="Örnek #",
                    yaxis_title="Kümülatif Doğruluk", height=380)
            fig.add_hline(y=0.5, line_dash="dot", line_color="gray")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.warning("Seçilen lambda/seed için veri bulunamadı.")

    # BES Cross-Fund Summary
    st.markdown("---")
    st.markdown("#### BES Çapraz-Fon Özeti")
    df_bes = L("summaries", "mcaware_BiLSTM_v3b_BES_CROSS_FUND_SUMMARY.csv")
    if df_bes is not None:
        st.dataframe(df_bes.style.format({
            c: "{:.4f}" for c in df_bes.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 6 — Ablation                                                       ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[5]:
    section(t("abl_title"))

    # Feature group ablation
    df_fa = L("summaries", "mcaware_feature_ablation_SUMMARY.csv")
    if df_fa is not None:
        st.markdown("#### Özellik Grubu Ablasyonu (full_13 vs no_ext_10)")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_fa["group"], y=df_fa["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_fa["group"], y=df_fa["mean_flip"], marker_color="#00FF00"))
        fig.add_trace(go.Bar(name="Naive Acc", x=df_fa["group"], y=df_fa["naive"], marker_color="#FFA500"))
        _layout(fig, barmode="group", title="Özellik Grubu: Model vs Flip vs Naive",
                xaxis_title="Grup", yaxis_title="Doğruluk", height=400)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_fa, use_container_width=True, hide_index=True)

    # Single feature ablation
    df_sfa = L("summaries", "mcaware_single_feat_ablation_SUMMARY.csv")
    if df_sfa is not None:
        st.markdown("---")
        st.markdown("#### Tekli Özellik Ablasyonu")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_sfa["group"], y=df_sfa["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_sfa["group"], y=df_sfa["mean_flip"], marker_color="#00FF00"))
        _layout(fig, barmode="group", title="Tek Özellik Çıkarma: Etki Analizi",
                xaxis_title="Grup", yaxis_title="Doğruluk", height=400)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_sfa, use_container_width=True, hide_index=True)

    # Input length ablation
    df_ila = L("summaries", "mcaware_inlen_ablation_SUMMARY.csv")
    if df_ila is not None:
        st.markdown("---")
        st.markdown("#### Giriş Uzunluğu Ablasyonu (IN_LEN = 2, 5, 10)")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_ila["IN_LEN"].astype(str), y=df_ila["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_ila["IN_LEN"].astype(str), y=df_ila["mean_flip"], marker_color="#00FF00"))
        fig.add_trace(go.Bar(name="Naive Acc", x=df_ila["IN_LEN"].astype(str), y=df_ila["naive"], marker_color="#FFA500"))
        _layout(fig, barmode="group", title="Giriş Uzunluğu: Model vs Flip vs Naive",
                xaxis_title="IN_LEN", yaxis_title="Doğruluk", height=400)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_ila, use_container_width=True, hide_index=True)

    finding_box(
        "Dış değişkenler (USDTRY, Brent Oil, TCMB faiz) eklendiğinde anti-prediktif davranış ortaya çıkıyor. "
        "Sadece iç değişkenlerle (no_ext_10) model nötr kalıyor. "
        "Her dış değişken tek tek çıkarıldığında bile anti-prediktif etki azalmıyor — "
        "bu, dış değişkenlerin birlikte bir sinerjik etki oluşturduğunu gösteriyor.",
        title="🔍 Ablation Bulgusu"
    )

    # Ablation raw RESULTS
    st.markdown("---")
    st.markdown("#### Ham Ablasyon Sonuçları")
    for aname, afile in [("Özellik Grubu", "mcaware_feature_ablation_RESULTS.csv"),
                          ("Tekli Özellik", "mcaware_single_feat_ablation_RESULTS.csv"),
                          ("Giriş Uzunluğu", "mcaware_inlen_ablation_RESULTS.csv")]:
        adf = L("summaries", afile)
        if adf is not None:
            with st.expander(f"📄 {aname} — Ham Sonuçlar"):
                st.dataframe(adf.style.format({
                    c: "{:.4f}" for c in adf.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 7 — Cross-Market & Multi-Stock                                     ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[6]:
    section(t("cross_title"))

    # BIST vs NASDAQ
    df_nq = L("summaries", "mcaware_nasdaq_SUMMARY.csv")
    if df_nq is not None:
        st.markdown("#### BIST vs NASDAQ Karşılaştırma")
        fig = go.Figure()
        labels = df_nq["market"] + " — " + df_nq["group"]
        fig.add_trace(go.Bar(name="Model Acc", x=labels, y=df_nq["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=labels, y=df_nq["mean_flip"], marker_color="#00FF00"))
        _layout(fig, barmode="group", title="BIST vs NASDAQ: Model vs Flip",
                xaxis_title="Pazar — Grup", yaxis_title="Doğruluk", height=400)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_nq, use_container_width=True, hide_index=True)

    # NASDAQ raw results
    df_nq_r = L("summaries", "mcaware_nasdaq_RESULTS.csv")
    if df_nq_r is not None:
        with st.expander("📄 NASDAQ Ham Sonuçlar (Seed Bazlı)"):
            st.dataframe(df_nq_r.style.format({
                c: "{:.4f}" for c in df_nq_r.select_dtypes("float").columns
            }), use_container_width=True, hide_index=True)

    # NASDAQ Correlation
    df_nq_corr = L("diagnostics", "mcaware_nasdaq_CORR.csv")
    if df_nq_corr is not None:
        with st.expander("📄 NASDAQ Korelasyon (Train vs Test)"):
            st.dataframe(df_nq_corr.style.format({
                c: "{:.4f}" for c in df_nq_corr.select_dtypes("float").columns
            }), use_container_width=True, hide_index=True)

    # GARAN Correlation
    df_g_corr = L("diagnostics", "mcaware_corr_GARAN.csv")
    if df_g_corr is not None:
        with st.expander("📄 GARAN Korelasyon Analizi"):
            st.dataframe(df_g_corr.style.format({
                c: "{:.4f}" for c in df_g_corr.select_dtypes("float").columns
            }), use_container_width=True, hide_index=True)

    # Correlation comparison
    df_corr = L("diagnostics", "mcaware_corr_COMPARISON.csv")
    if df_corr is not None:
        st.markdown("---")
        st.markdown("#### Korelasyon Karşılaştırma (Train vs Test)")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Train Corr", x=df_corr["variable"], y=df_corr["cor_train"], marker_color="#00BFFF"))
        fig.add_trace(go.Bar(name="Test Corr", x=df_corr["variable"], y=df_corr["cor_test"], marker_color="#FF416C"))
        _layout(fig, barmode="group", title="Değişken Korelasyonu: Train vs Test",
                xaxis_title="Değişken", yaxis_title="Korelasyon", height=380)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_corr.style.format({
            c: "{:.4f}" for c in df_corr.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # Correlation analysis
    df_ca = L("diagnostics", "mcaware_corr_analysis.csv")
    if df_ca is not None:
        st.markdown("---")
        st.markdown("#### Korelasyon Analizi (Detaylı)")
        fig = go.Figure()
        for metric in df_ca["metric"].unique():
            sub = df_ca[df_ca["metric"] == metric]
            fig.add_trace(go.Bar(name=f"Train ({metric})", x=sub["variable"],
                                 y=sub["cor_train"], offsetgroup=metric))
        _layout(fig, barmode="group", title="Korelasyon Analizi: Değişken × Metrik",
                xaxis_title="Değişken", yaxis_title="Korelasyon", height=400)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_ca.style.format({
            c: "{:.4f}" for c in df_ca.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    st.markdown("---")

    # Multi-stock BIST-3
    df_ms = L("summaries", "mcaware_bist_multi_stock_SUMMARY.csv")
    if df_ms is not None:
        st.markdown("#### Multi-Stock BIST (3 Hisse)")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_ms["ticker"], y=df_ms["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_ms["ticker"], y=df_ms["mean_flip"], marker_color="#00FF00"))
        fig.add_trace(go.Bar(name="Naive Acc", x=df_ms["ticker"], y=df_ms["naive"], marker_color="#FFA500"))
        _layout(fig, barmode="group", title="BIST 3-Stock: Model vs Flip vs Naive",
                xaxis_title="Hisse", yaxis_title="Doğruluk", height=400)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_ms, use_container_width=True, hide_index=True)

    # Multi-stock raw RESULTS
    df_ms_r = L("summaries", "mcaware_bist_multi_stock_RESULTS.csv")
    if df_ms_r is not None:
        with st.expander("📄 Multi-Stock Ham Sonuçlar"):
            st.dataframe(df_ms_r, use_container_width=True, hide_index=True)

    # Holding (5 stocks)
    df_hold = L("summaries", "mcaware_bist5_holding_SUMMARY.csv")
    if df_hold is not None:
        st.markdown("---")
        st.markdown("#### BIST-5 Holding")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_hold["ticker"], y=df_hold["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_hold["ticker"], y=df_hold["mean_flip"], marker_color="#00FF00"))
        fig.add_trace(go.Bar(name="Naive Acc", x=df_hold["ticker"], y=df_hold["naive"], marker_color="#FFA500"))
        _layout(fig, barmode="group", title="Holding: Model vs Flip vs Naive",
                xaxis_title="Hisse", yaxis_title="Doğruluk", height=400)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_hold, use_container_width=True, hide_index=True)

    # Holding STRICT + RESULTS
    df_hold_s = L("summaries", "mcaware_bist5_holding_STRICT.csv")
    if df_hold_s is not None:
        with st.expander("📄 Holding — Strict Anti-Prediktif Analiz"):
            st.dataframe(df_hold_s.style.format({
                c: "{:.4f}" for c in df_hold_s.select_dtypes("float").columns
            }), use_container_width=True, hide_index=True)
    df_hold_r = L("summaries", "mcaware_bist5_holding_RESULTS.csv")
    if df_hold_r is not None:
        with st.expander("📄 Holding — Ham Sonuçlar"):
            st.dataframe(df_hold_r, use_container_width=True, hide_index=True)

    # Sigorta
    df_sig = L("summaries", "mcaware_bist5_sigorta_SUMMARY.csv")
    if df_sig is not None:
        st.markdown("---")
        st.markdown("#### BIST-5 Sigorta")
        st.dataframe(df_sig, use_container_width=True, hide_index=True)

    # Sigorta STRICT + RESULTS
    df_sig_s = L("summaries", "mcaware_bist5_sigorta_STRICT.csv")
    if df_sig_s is not None:
        with st.expander("📄 Sigorta — Strict Anti-Prediktif Analiz"):
            st.dataframe(df_sig_s.style.format({
                c: "{:.4f}" for c in df_sig_s.select_dtypes("float").columns
            }), use_container_width=True, hide_index=True)
    df_sig_r = L("summaries", "mcaware_bist5_sigorta_RESULTS.csv")
    if df_sig_r is not None:
        with st.expander("📄 Sigorta — Ham Sonuçlar"):
            st.dataframe(df_sig_r, use_container_width=True, hide_index=True)

    # Sigorta V2
    df_sig2 = L("summaries", "mcaware_bist5_sigorta_v2_SUMMARY.csv")
    if df_sig2 is not None:
        st.markdown("#### BIST-5 Sigorta V2")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_sig2["ticker"], y=df_sig2["mean_acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_sig2["ticker"], y=df_sig2["mean_flip"], marker_color="#00FF00"))
        fig.add_trace(go.Bar(name="Naive Acc", x=df_sig2["ticker"], y=df_sig2["naive"], marker_color="#FFA500"))
        _layout(fig, barmode="group", title="Sigorta V2: Model vs Flip vs Naive",
                xaxis_title="Hisse", yaxis_title="Doğruluk", height=400)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_sig2, use_container_width=True, hide_index=True)

    # Sigorta Attention
    df_siga = L("summaries", "mcaware_bist5_sigorta_attention_SUMMARY.csv")
    if df_siga is not None:
        st.markdown("#### BIST-5 Sigorta — Attention")
        st.dataframe(df_siga, use_container_width=True, hide_index=True)

    # Sigorta Attention RESULTS + V2 RESULTS
    df_siga_r = L("summaries", "mcaware_bist5_sigorta_attention_RESULTS.csv")
    if df_siga_r is not None:
        with st.expander("📄 Sigorta Attention — Ham Sonuçlar"):
            st.dataframe(df_siga_r, use_container_width=True, hide_index=True)
    df_sig2_r = L("summaries", "mcaware_bist5_sigorta_v2_RESULTS.csv")
    if df_sig2_r is not None:
        with st.expander("📄 Sigorta V2 — Ham Sonuçlar"):
            st.dataframe(df_sig2_r, use_container_width=True, hide_index=True)

    # BES Individual Summaries
    st.markdown("---")
    st.markdown("#### BES Fon Bireysel Özetleri")
    for bfund, bfile in [("ALZ", "mcaware_BiLSTM_v3b_BES_ALZ_SUMMARY.csv"),
                         ("AMZ", "mcaware_BiLSTM_v3b_BES_AMZ_SUMMARY.csv"),
                         ("AZS", "mcaware_BiLSTM_v3b_BES_AZS_SUMMARY.csv")]:
        bdf = L("summaries", bfile)
        if bdf is not None:
            with st.expander(f"📄 BES {bfund} — Detay"):
                st.dataframe(bdf.style.format({
                    c: "{:.4f}" for c in bdf.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)
    for bfund, bfile in [("ALZ", "mcaware_BiLSTM_v3b_BES_ALZ_OPTIMAL.csv"),
                         ("AMZ", "mcaware_BiLSTM_v3b_BES_AMZ_OPTIMAL.csv"),
                         ("AZS", "mcaware_BiLSTM_v3b_BES_AZS_OPTIMAL.csv")]:
        bdf = L("summaries", bfile)
        if bdf is not None:
            with st.expander(f"🏆 BES {bfund} — Optimal Konfigürasyon"):
                st.dataframe(bdf.style.format({
                    c: "{:.4f}" for c in bdf.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)

    # Seed Variance
    df_sv = L("diagnostics", "mcaware_bist5_sigorta_v2_SEED_VAR.csv")
    if df_sv is not None:
        st.markdown("---")
        st.markdown("#### Seed Varyansı (Sigorta V2)")
        fig = go.Figure()
        fig.add_trace(go.Bar(x=df_sv["ticker"], y=df_sv["acc_mean"], name="Acc Mean",
                             error_y=dict(type="data", array=df_sv["acc_std"]),
                             marker_color="#FF416C"))
        _layout(fig, title="Seed Varyansı: Ortalama ± Std", xaxis_title="Hisse",
                yaxis_title="Doğruluk", height=380)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_sv.style.format({
            c: "{:.4f}" for c in df_sv.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 8 — Ensemble & Baseline                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[7]:
    section(t("ens_title"))

    # Ensemble results
    df_ens = L("summaries", "mcaware_ensemble_RESULTS.csv")
    if df_ens is not None:
        st.markdown("#### Ensemble Sonuçları (6 Mimari + Hard + Soft)")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc", x=df_ens["name"], y=df_ens["Acc"], marker_color="#FF416C"))
        fig.add_trace(go.Bar(name="Flip Acc", x=df_ens["name"], y=df_ens["Acc_flip"], marker_color="#00FF00"))
        _layout(fig, barmode="group", title="Ensemble: Model vs Flip", height=420,
                xaxis_title="Model/Ensemble", yaxis_title="Doğruluk")
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_ens.style.format({
            c: "{:.4f}" for c in df_ens.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # Hard votes analysis
    df_hv = L("predictions", "mcaware_ensemble_HARD_VOTES.csv")
    if df_hv is not None:
        st.markdown("---")
        st.markdown("#### Hard Vote Analizi")

        # Vote distribution
        vote_counts = df_hv["n_votes_up"].value_counts().sort_index()
        fig = px.bar(x=vote_counts.index, y=vote_counts.values,
                     labels={"x": "Up Oy Sayısı (0-6)", "y": "Örnek Sayısı"},
                     color=vote_counts.index, color_continuous_scale="RdYlGn")
        _layout(fig, title="Oy Dağılımı (Kaç mimari 'Up' dedi?)", height=350)
        st.plotly_chart(fig, use_container_width=True)

        # Accuracy by vote count
        acc_by_vote = []
        for nv in sorted(df_hv["n_votes_up"].unique()):
            sub = df_hv[df_hv["n_votes_up"] == nv]
            n_total = len(sub)
            if nv >= 4:  # majority says UP
                correct = (sub["y_true"] == 1).sum()
            else:        # majority says DOWN
                correct = (sub["y_true"] == 0).sum()
            acc_by_vote.append({"n_votes_up": nv, "n_samples": n_total,
                                "accuracy": correct / n_total if n_total > 0 else 0})
        acc_vote_df = pd.DataFrame(acc_by_vote)
        fig = px.bar(acc_vote_df, x="n_votes_up", y="accuracy",
                     text="n_samples", color="accuracy",
                     color_continuous_scale="RdYlGn",
                     labels={"n_votes_up": "Up Oy Sayısı", "accuracy": "Doğruluk"})
        _layout(fig, title="Oy Sayısına Göre Doğruluk (Konsensüs bile yardımcı olmuyor)", height=380)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)

        finding_box(
            "6 mimarinin tamamı aynı yönde oy verse bile doğruluk %50'yi geçemiyor. "
            "Konsensüs, anti-prediktif davranışı çözemiyor — tüm modeller aynı yönde yanılıyor.",
            title="🗳️ Ensemble Bulgusu"
        )

    # Soft votes
    df_sv_ens = L("predictions", "mcaware_ensemble_SOFT_VOTES.csv")
    if df_sv_ens is not None:
        st.markdown("---")
        st.markdown("#### Soft Vote Analizi")
        fig = px.histogram(df_sv_ens, x="yhat_soft", color="y_true", nbins=40,
                           barmode="overlay", color_discrete_map={0: "#FF4444", 1: "#00FF00"},
                           labels={"yhat_soft": "Soft Vote (Ortalama ŷ)", "y_true": "Gerçek"})
        fig.add_vline(x=0.5, line_dash="dash", line_color="white")
        _layout(fig, title="Soft Vote Dağılımı", height=380)
        st.plotly_chart(fig, use_container_width=True)

    # Rule-based baselines
    st.markdown("---")
    st.markdown("#### Kural Tabanlı Baseline Modeller")
    rb_files = [
        ("THYAO", "mcaware_rule_based_RESULTS.csv"),
        ("AAPL",  "mcaware_rule_based_AAPL_RESULTS.csv"),
        ("GARAN", "mcaware_rule_based_GARAN_RESULTS.csv"),
    ]
    for name, fname in rb_files:
        df_rb = L("summaries", fname)
        if df_rb is not None:
            with st.expander(f"📄 Kural Tabanlı — {name}"):
                st.dataframe(df_rb.style.format({
                    c: "{:.4f}" for c in df_rb.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)

    # Technical indicators
    df_ti = L("summaries", "mcaware_majority_rules_10ind_SUMMARY.csv")
    if df_ti is not None:
        st.markdown("---")
        st.markdown("#### Teknik İndikatörler (10 İndikatör)")
        fig = go.Figure()
        fig.add_trace(go.Bar(x=df_ti["method"], y=df_ti["accuracy"], name="Accuracy",
                             marker_color="#00BFFF"))
        fig.add_trace(go.Scatter(x=df_ti["method"], y=df_ti["naive_acc"], name="Naive",
                                 mode="lines+markers", line=dict(color="#FFA500", dash="dash")))
        _layout(fig, title="Teknik İndikatör Doğrulukları", height=400,
                xaxis_title="Yöntem", yaxis_title="Doğruluk")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_ti, use_container_width=True, hide_index=True)

    # Voting Score Meta
    df_vsm = L("summaries", "mcaware_voting_score_meta_RESULTS.csv")
    if df_vsm is not None:
        st.markdown("---")
        st.markdown("#### Voting Score Meta Analizi")
        # Accuracy by voting score
        if "voting_score" in df_vsm.columns and "actual" in df_vsm.columns:
            acc_vs = []
            for vs in sorted(df_vsm["voting_score"].unique()):
                sub = df_vsm[df_vsm["voting_score"] == vs]
                majority = 1 if vs > 0 else 0
                correct = (sub["actual"] == majority).sum()
                acc_vs.append({"voting_score": vs, "n": len(sub),
                               "accuracy": correct / len(sub) if len(sub) > 0 else 0})
            vdf = pd.DataFrame(acc_vs)
            fig = px.bar(vdf, x="voting_score", y="accuracy", text="n",
                         color="accuracy", color_continuous_scale="RdYlGn",
                         labels={"voting_score": "Voting Score", "accuracy": "Doğruluk"})
            _layout(fig, title="Voting Score'a Göre Doğruluk", height=400)
            fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
            st.plotly_chart(fig, use_container_width=True)
        with st.expander("📄 Voting Score Meta — Tüm Veriler"):
            st.dataframe(df_vsm, use_container_width=True, hide_index=True)

    # Majority Rules Matrix
    df_mrm = L("summaries", "mcaware_majority_rules_10ind_MATRIX.csv")
    if df_mrm is not None:
        st.markdown("---")
        st.markdown("#### Teknik İndikatör Oylama Matrisi")
        st.dataframe(df_mrm, use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 9 — İstatistiksel Kanıtlar                                         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[8]:
    section(t("stat_title"))

    # Mutual Information
    df_mi = L("diagnostics", "mcaware_v4_MI_SCORES.csv")
    if df_mi is not None:
        st.markdown("#### Mutual Information (MI) Skorları")
        fig = px.bar(df_mi, x="dataset", y="MI_bit", color="interpretation",
                     text="MI_bit",
                     labels={"dataset": "Veri Seti", "MI_bit": "MI (bit)", "interpretation": "Yorum"})
        _layout(fig, title="Mutual Information Skorları", height=420)
        fig.update_traces(texttemplate="%{text:.3f}", textposition="outside")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_mi, use_container_width=True, hide_index=True)

    # MI Calibration
    df_mic = L("diagnostics", "mcaware_v5_MI_CALIBRATION.csv")
    if df_mic is not None:
        st.markdown("---")
        st.markdown("#### MI Kalibrasyon")
        st.dataframe(df_mic, use_container_width=True, hide_index=True)

        if "verdict" in df_mic.columns:
            for _, row in df_mic.iterrows():
                ds = row.get("dataset", "")
                verdict = row.get("verdict", "")
                color = "#FF4444" if "BIAS" in str(verdict) else "#FFA500" if "AMBIGUOUS" in str(verdict) else "#00FF00"
                st.markdown(f"<span style='color:{color};'>**{ds}:** {verdict}</span>", unsafe_allow_html=True)

    # Label Check
    df_lc = L("diagnostics", "mcaware_v4_LABEL_CHECK.csv")
    if df_lc is not None:
        st.markdown("---")
        st.markdown("#### Label Check (Tanı)")

        # Highlight diagnosis column
        diag_counts = df_lc["diagnosis"].value_counts()
        for diag, cnt in diag_counts.items():
            color = "#FF4444" if "BUG" in str(diag) or "CONTRARIAN" in str(diag) else "#00FF00"
            st.markdown(f"<span style='color:{color};'>**{diag}:** {cnt} konfigürasyon</span>",
                        unsafe_allow_html=True)

        st.dataframe(df_lc.style.format({
            c: "{:.4f}" for c in df_lc.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # Correlation analysis (also shown here)
    df_ca2 = L("diagnostics", "mcaware_corr_analysis.csv")
    if df_ca2 is not None:
        st.markdown("---")
        st.markdown("#### Korelasyon Analizi")
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Train Corr", x=df_ca2["variable"] + " (" + df_ca2["metric"] + ")",
                             y=df_ca2["cor_train"], marker_color="#00BFFF"))
        fig.add_trace(go.Bar(name="Test Corr", x=df_ca2["variable"] + " (" + df_ca2["metric"] + ")",
                             y=df_ca2["cor_test"], marker_color="#FF416C"))
        _layout(fig, barmode="group", title="Train vs Test Korelasyon Kayması",
                xaxis_title="Değişken (Metrik)", yaxis_title="Korelasyon", height=400)
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_ca2.style.format({
            c: "{:.4f}" for c in df_ca2.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # McNemar (also shown here for completeness)
    df_mcn2 = L("diagnostics", "mcaware_multi_arch_McNEMAR.csv")
    if df_mcn2 is not None:
        st.markdown("---")
        st.markdown("#### McNemar Testi Sonuçları")
        st.dataframe(df_mcn2.style.format({
            c: "{:.4f}" for c in df_mcn2.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

    # YHAT Stats
    df_yhat = L("diagnostics", "mcaware_BiLSTM_v3THYAO_YHAT_STATS.csv")
    if df_yhat is not None:
        st.markdown("---")
        st.markdown("#### ŷ İstatistikleri (BiLSTM v3 THYAO)")
        fig = go.Figure()
        fig.add_trace(go.Scatter(x=df_yhat.index, y=df_yhat["test_mean"], mode="markers+lines",
                                 name="Test Mean ŷ", marker=dict(color="#FF416C", size=8),
                                 error_y=dict(type="data", array=df_yhat["test_sd"])))
        _layout(fig, title="ŷ Test Ortalaması ± Std (Seed × Lambda)", height=400,
                xaxis_title="Konfigürasyon #", yaxis_title="ŷ Ortalaması")
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray", annotation_text="0.5")
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(df_yhat.style.format({
            c: "{:.4f}" for c in df_yhat.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 10 — Threshold & Diagnostics                                       ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[9]:
    section(t("diag_title"))

    # Threshold grid selector
    thr_files = {
        "BiLSTM v3 THYAO":   "mcaware_BiLSTM_v3THYAO_THRESHOLD_GRID.csv",
        "BiLSTM v2a":        "mcaware_BiLSTM_v2a_THRESHOLD_GRID.csv",
        "BiLSTM v2b":        "mcaware_BiLSTM_v2b_THRESHOLD_GRID.csv",
        "BiLSTM v2bfix":     "mcaware_BiLSTM_v2bfix_THRESHOLD_GRID.csv",
        "BiLSTM v3b GARAN":  "mcaware_BiLSTM_v3b_GARAN_THRESHOLD_GRID.csv",
        "BiLSTM v3b Window": "mcaware_BiLSTM_v3b_window_THRESHOLD_GRID.csv",
        "BiLSTM v3c no_cw":  "mcaware_BiLSTM_v3c_no_cw_THRESHOLD_GRID.csv",
        "BiLSTM attn v6":    "mcaware_BiLSTM_attn_v6_THRESHOLD_GRID.csv",
        "Conv1D":            "mcaware_multi_arch_Conv1D_THRESHOLD_GRID.csv",
        "GRU":               "mcaware_multi_arch_GRU_THRESHOLD_GRID.csv",
        "SimpleRNN":         "mcaware_multi_arch_SimpleRNN_THRESHOLD_GRID.csv",
        "TCN":               "mcaware_multi_arch_TCN_THRESHOLD_GRID.csv",
        "Transformer":       "mcaware_multi_arch_Transformer_THRESHOLD_GRID.csv",
    }

    sel_thr = st.selectbox("Threshold Grid Seçin", list(thr_files.keys()))
    df_thr = L("thresholds", thr_files[sel_thr])

    if df_thr is not None:
        # Line chart: accuracy as function of threshold for each lambda
        st.markdown("#### Eşik → Doğruluk (Lambda bazlı)")
        fig = go.Figure()
        for lam in sorted(df_thr["lambda"].unique()):
            sub = df_thr[df_thr["lambda"] == lam]
            # Average across seeds
            avg = sub.groupby("threshold")["Acc_test"].mean().reset_index()
            fig.add_trace(go.Scatter(x=avg["threshold"], y=avg["Acc_test"],
                                     mode="lines+markers", name=f"λ={lam}"))
        _layout(fig, title=f"{sel_thr}: Eşik vs Test Doğruluğu",
                xaxis_title="Eşik", yaxis_title="Test Acc", height=420)
        fig.add_hline(y=0.5, line_dash="dash", line_color="gray")
        st.plotly_chart(fig, use_container_width=True)

        # Heatmap: threshold × lambda → accuracy (averaged over seeds)
        st.markdown("#### Eşik × Lambda → Doğruluk Isı Haritası")
        pivot = df_thr.groupby(["lambda", "threshold"])["Acc_test"].mean().reset_index()
        pivot_table = pivot.pivot(index="lambda", columns="threshold", values="Acc_test")
        fig = px.imshow(
            pivot_table.values,
            x=[f"{c:.2f}" for c in pivot_table.columns],
            y=[f"λ={r}" for r in pivot_table.index],
            text_auto=".3f",
            color_continuous_scale="RdYlGn",
            labels=dict(color="Acc_test"),
            aspect="auto",
        )
        _layout(fig, title=f"{sel_thr}: Eşik × Lambda → Doğruluk", height=350)
        st.plotly_chart(fig, use_container_width=True)

        with st.expander("📄 Ham Threshold Grid Verisi"):
            st.dataframe(df_thr.style.format({
                c: "{:.4f}" for c in df_thr.select_dtypes("float").columns
            }), use_container_width=True, hide_index=True)

    # YHAT Stats tables
    st.markdown("---")
    st.markdown("#### ŷ İstatistikleri (Tüm Modeller)")
    yhat_files = [
        ("BiLSTM v3 THYAO",   "mcaware_BiLSTM_v3THYAO_YHAT_STATS.csv"),
        ("BiLSTM v2b",        "mcaware_BiLSTM_v2b_YHAT_STATS.csv"),
        ("BiLSTM v2bfix",     "mcaware_BiLSTM_v2bfix_YHAT_STATS.csv"),
        ("BiLSTM v3b GARAN",  "mcaware_BiLSTM_v3b_GARAN_YHAT_STATS.csv"),
        ("BiLSTM v3b Window", "mcaware_BiLSTM_v3b_window_YHAT_STATS.csv"),
        ("BiLSTM v3c no_cw",  "mcaware_BiLSTM_v3c_no_cw_YHAT_STATS.csv"),
        ("BiLSTM attn v6",    "mcaware_BiLSTM_attn_v6_YHAT_STATS.csv"),
        ("BES ALZ",           "mcaware_BiLSTM_v3b_BES_ALZ_YHAT_STATS.csv"),
        ("BES AMZ",           "mcaware_BiLSTM_v3b_BES_AMZ_YHAT_STATS.csv"),
        ("BES AZS",           "mcaware_BiLSTM_v3b_BES_AZS_YHAT_STATS.csv"),
        ("Conv1D",            "mcaware_multi_arch_Conv1D_YHAT_STATS.csv"),
        ("GRU",               "mcaware_multi_arch_GRU_YHAT_STATS.csv"),
        ("SimpleRNN",         "mcaware_multi_arch_SimpleRNN_YHAT_STATS.csv"),
        ("TCN",               "mcaware_multi_arch_TCN_YHAT_STATS.csv"),
        ("Transformer",       "mcaware_multi_arch_Transformer_YHAT_STATS.csv"),
    ]
    for name, fname in yhat_files:
        df_y = L("diagnostics", fname)
        if df_y is not None:
            with st.expander(f"📊 {name}"):
                st.dataframe(df_y.style.format({
                    c: "{:.4f}" for c in df_y.select_dtypes("float").columns
                }), use_container_width=True, hide_index=True)

    # Seed report
    df_sr = L("diagnostics", "mcaware_BiLSTM_v1_SEED_REPORT.csv")
    if df_sr is not None:
        st.markdown("---")
        st.markdown("#### Seed Raporu (BiLSTM v1)")
        st.dataframe(df_sr.style.format({
            c: "{:.4f}" for c in df_sr.select_dtypes("float").columns
        }), use_container_width=True, hide_index=True)

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  TAB 11 — Karşılaştırma Modu                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
with tabs[10]:
    section("Karşılaştırma Modu")
    st.markdown("""
    <div style="background: linear-gradient(90deg, #FF416C22, #FF4B2B22);
                border-radius: 10px; padding: 15px; border-left: 4px solid #FF416C;">
        <b>⚔️ İki mimari veya versiyonu yan yana karşılaştırın.</b>
        Her metriği görsel olarak karşılaştırarak hangi modelin nasıl performans gösterdiğini anında görün.
    </div>
    """, unsafe_allow_html=True)

    # Build comparison options from available data
    cmp_options = {}
    # Architectures
    df_arch_cmp = L("summaries", "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv")
    if df_arch_cmp is not None:
        for _, row in df_arch_cmp.iterrows():
            cmp_options[f"🏗️ {row['arch']}"] = {
                "Model Acc": row["mean_acc"], "Flip Acc": row["mean_acc_flip"],
                "Naive": row["naive_acc"], "Flip>Naive": row["flip_beats_naive_count"],
                "MC Trap": row["mc_count"], "type": "arch"
            }
    # BiLSTM versions
    ver_files = [
        ("v1",       "mcaware_BiLSTM_v1_SUMMARY.csv"),
        ("v2a",      "mcaware_BiLSTM_v2a_SUMMARY.csv"),
        ("v2b",      "mcaware_BiLSTM_v2b_SUMMARY.csv"),
        ("v2bfix",   "mcaware_BiLSTM_v2bfix_SUMMARY.csv"),
        ("v3_THYAO", "mcaware_BiLSTM_v3THYAO_SUMMARY.csv"),
        ("v3b_GARAN","mcaware_BiLSTM_v3b_GARAN_SUMMARY.csv"),
        ("v3c_noCW", "mcaware_BiLSTM_v3c_no_cw_SUMMARY.csv"),
        ("v3b_window","mcaware_BiLSTM_v3b_window_SUMMARY.csv"),
        ("attn_v6",  "mcaware_BiLSTM_attn_v6_SUMMARY.csv"),
    ]
    for vname, fname in ver_files:
        vdf = L("summaries", fname)
        if vdf is not None:
            lam0 = vdf[vdf["lambda"] == 0] if "lambda" in vdf.columns else vdf.iloc[:1]
            if not lam0.empty:
                row = lam0.iloc[0]
                acc = row.get("Acc_05", row.get("Acc_m", 0))
                flip = row.get("Acc_flip_05", 1 - acc if acc else 0)
                spec = row.get("Spec_05", row.get("Spec_m", 0))
                sens = row.get("Sens_05", row.get("Sens_m", 0))
                cmp_options[f"🧬 BiLSTM {vname}"] = {
                    "Model Acc": acc, "Flip Acc": flip,
                    "Spec": spec, "Sens": sens, "type": "version"
                }

    if len(cmp_options) >= 2:
        keys = list(cmp_options.keys())
        col_a, col_b = st.columns(2)
        with col_a:
            sel_a = st.selectbox("Model A", keys, index=0)
        with col_b:
            sel_b = st.selectbox("Model B", keys, index=min(1, len(keys)-1))

        data_a = cmp_options[sel_a]
        data_b = cmp_options[sel_b]

        # Side-by-side metrics
        st.markdown("---")
        st.markdown("#### 📊 Metrik Karşılaştırma")

        shared_keys = [k for k in data_a if k in data_b and k != "type"]
        for metric in shared_keys:
            va = data_a[metric]
            vb = data_b[metric]
            mc1, mc2, mc3 = st.columns([2, 1, 2])
            with mc1:
                color_a = "#00FF00" if (isinstance(va, (int, float)) and isinstance(vb, (int, float)) and va > vb) else "#FF4444"
                val_str = f"{va:.4f}" if isinstance(va, float) else str(va)
                st.markdown(f"<div style='text-align:center; font-size:1.5rem; font-weight:700; color:{color_a}'>{val_str}</div>",
                            unsafe_allow_html=True)
            with mc2:
                st.markdown(f"<div style='text-align:center; color:#888; padding-top:5px;'>{metric}</div>",
                            unsafe_allow_html=True)
            with mc3:
                color_b = "#00FF00" if (isinstance(va, (int, float)) and isinstance(vb, (int, float)) and vb > va) else "#FF4444"
                val_str = f"{vb:.4f}" if isinstance(vb, float) else str(vb)
                st.markdown(f"<div style='text-align:center; font-size:1.5rem; font-weight:700; color:{color_b}'>{val_str}</div>",
                            unsafe_allow_html=True)

        # Radar chart comparison
        st.markdown("---")
        st.markdown("#### 🕸️ Radar Karşılaştırma")
        float_keys = [k for k in shared_keys if isinstance(data_a[k], float) and isinstance(data_b[k], float)]
        if float_keys:
            fig = go.Figure()
            fig.add_trace(go.Scatterpolar(
                r=[data_a[k] for k in float_keys] + [data_a[float_keys[0]]],
                theta=float_keys + [float_keys[0]],
                fill='toself', name=sel_a, fillcolor="rgba(255,65,108,0.3)",
                line=dict(color="#FF416C", width=2)
            ))
            fig.add_trace(go.Scatterpolar(
                r=[data_b[k] for k in float_keys] + [data_b[float_keys[0]]],
                theta=float_keys + [float_keys[0]],
                fill='toself', name=sel_b, fillcolor="rgba(0,255,0,0.2)",
                line=dict(color="#00FF00", width=2)
            ))
            fig.update_layout(
                polar=dict(
                    bgcolor="rgba(0,0,0,0)",
                    radialaxis=dict(visible=True, range=[0, max(max(data_a[k] for k in float_keys), max(data_b[k] for k in float_keys)) * 1.1]),
                ),
                paper_bgcolor="rgba(0,0,0,0)",
                font=dict(color="white"),
                height=500,
                showlegend=True,
                legend=dict(font=dict(size=14)),
            )
            st.plotly_chart(fig, use_container_width=True)

        # Bar chart comparison
        st.markdown("#### 📊 Bar Karşılaştırma")
        if float_keys:
            fig = go.Figure()
            fig.add_trace(go.Bar(name=sel_a, x=float_keys, y=[data_a[k] for k in float_keys], marker_color="#FF416C"))
            fig.add_trace(go.Bar(name=sel_b, x=float_keys, y=[data_b[k] for k in float_keys], marker_color="#00FF00"))
            _layout(fig, barmode="group", title=f"{sel_a} vs {sel_b}", height=420,
                    xaxis_title="Metrik", yaxis_title="Değer")
            fig.add_hline(y=0.5, line_dash="dash", line_color="gray", annotation_text="Şans (%50)")
            st.plotly_chart(fig, use_container_width=True)

        # Winner summary
        st.markdown("---")
        wins_a = sum(1 for k in float_keys if data_a[k] > data_b[k])
        wins_b = sum(1 for k in float_keys if data_b[k] > data_a[k])
        if wins_a > wins_b:
            winner = sel_a
            win_color = "#FF416C"
        elif wins_b > wins_a:
            winner = sel_b
            win_color = "#00FF00"
        else:
            winner = "Berabere"
            win_color = "#FFA500"
        st.markdown(f"""
        <div style="text-align:center; padding: 20px; border-radius: 10px;
                    background: linear-gradient(135deg, {win_color}22, {win_color}11);">
            <div style="font-size: 1rem; color: #888;">Kazanan</div>
            <div style="font-size: 2rem; font-weight: 800; color: {win_color};">{winner}</div>
            <div style="color: #aaa;">{wins_a} — {wins_b} (metrik bazında)</div>
        </div>
        """, unsafe_allow_html=True)


st.markdown("---")
st.markdown(
    """<div style="text-align:center;color:#666;font-size:0.8rem;">
    MC-AWARE  ·  TÜBİTAK 2209-A  ·  Hacettepe Üniversitesi  ·  2026
    <br>Tüm veriler gerçek deneylerden elde edilmiştir. Yapay veri kullanılmamıştır.
    </div>""",
    unsafe_allow_html=True,
)

import streamlit as st
import pandas as pd
import numpy as np
import plotly.graph_objects as go
from pathlib import Path
import os

# ─── CONFIG ───
st.set_page_config(
    page_title="MC-AWARE | Gercek Arastirma Sonuclari",
    page_icon="🔬", layout="wide", initial_sidebar_state="expanded"
)
st.markdown("""
<style>
    .main-title {font-size:2.5rem;font-weight:bold;background:-webkit-linear-gradient(45deg,#FF4B2B,#FF416C);-webkit-background-clip:text;-webkit-text-fill-color:transparent;}
    .sub-title {font-size:1rem;color:#888;margin-bottom:1.5rem;}
    .mc {background:#1E1E1E;padding:16px;border-radius:10px;box-shadow:0 4px 6px rgba(0,0,0,.3);text-align:center;border:1px solid #333;}
    .sg {color:#00FF00;font-size:1.7rem;font-weight:bold;} .sr {color:#FF4444;font-size:1.7rem;font-weight:bold;} .so {color:#FFA500;font-size:1.7rem;font-weight:bold;}
    .fb {background:linear-gradient(135deg,#1a1a2e,#16213e);border-left:4px solid #FF416C;padding:14px;border-radius:8px;margin:10px 0;}
</style>""", unsafe_allow_html=True)

BASE = Path(os.path.dirname(os.path.abspath(__file__)))
S = BASE / "Sonuclar" / "summaries"
P = BASE / "Sonuclar" / "predictions"
D = BASE / "Sonuclar" / "diagnostics"
TH = BASE / "Sonuclar" / "thresholds"

@st.cache_data
def L(folder, name):
    fp = folder / name
    return pd.read_csv(fp) if fp.exists() else None

def card(title, value, sub, css="so"):
    st.markdown(f'<div class="mc"><h4 style="color:#888;">{title}</h4><div class="{css}">{value}</div><p style="color:#aaa;font-size:.82rem;">{sub}</p></div>', unsafe_allow_html=True)

def finding(title, text):
    st.markdown(f'<div class="fb"><h4 style="color:#FF416C;">{title}</h4><p style="color:#ddd;">{text}</p></div>', unsafe_allow_html=True)

# ─── HEADER ───
st.markdown('<p class="main-title">MC-AWARE Arastirma Sonuclari</p>', unsafe_allow_html=True)
st.markdown('<p class="sub-title">TUBiTAK 2209-A | 6 DL Mimarisi · 350+ Konfigurasyon · 10+ Deney Serisi — Tamami Gercek Veri</p>', unsafe_allow_html=True)

# ─── TABS ───
tab1, tab2, tab3, tab4, tab5, tab6, tab7 = st.tabs([
    "📊 Ana Bulgular", "🏗️ Mimari Karsilastirma", "📈 Walk-Forward",
    "🔍 Tahmin Analizi", "🧪 Ablation", "🌍 Cross-Market", "🗳️ Ensemble & Baseline"
])

# ═══════════ TAB 1: ANA BULGULAR ═══════════
with tab1:
    st.markdown("### 🔬 Anti-Prediktif Davranis Kesfedildi")
    arch = L(S, "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv")
    cm = L(S, "mcaware_pooled_confusion_matrix.csv")
    if arch is not None:
        tc = int(arch["n_config"].sum()); tfb = int(arch["flip_beats_naive_count"].sum())
        tmc = int(arch["mc_count"].sum()); naive = float(arch["naive_acc"].iloc[0])
        c1,c2,c3,c4 = st.columns(4)
        with c1: card("Test Edilen Konfig", str(tc), f"7 mimari × {arch['n_config'].iloc[0]} konfig")
        with c2: card("MC Tuzagina Dusen", f"{tmc} / {tc}", "MC-Aware Loss %100 basarili", "sg")
        with c3: card("Flip > Naive", f"{tfb} / {tc}", "Anti-prediktif davranis", "sr")
        with c4: card("Anti-Prediktif Oran", f"%{tfb/tc*100:.0f}", "p ≈ 3×10⁻¹⁴", "sr")
        st.markdown("---")
        finding("⚡ Anahtar Bulgu",
            "Tum DL mimarilerinde modeller <b>rastgele tahminden daha kotu</b> performans gosteriyor. "
            "Ancak tahminleri <b>ters cevirdigimizde</b> rastgele tahminden <b>daha iyi</b> sonuc elde ediliyor.<br><br>"
            "Bu, modellerin piyasa sinyallerini <b>algiladigini ama sistematik olarak ters yorumladigini</b> gosterir. "
            "Binom testi ile bu sonucun rastlantisal olma olasiligi <b>p ≈ 3×10⁻¹⁴</b> olarak hesaplandi.")

    # Confusion Matrix
    if cm is not None:
        st.markdown("### 📋 Havuzlanmis Confusion Matrix")
        st.caption("Walk-forward fold'larindan toplanan gercek sonuclar")
        cmd = dict(zip(cm["metric"], cm["value"]))
        tp=int(cmd.get("TP",0)); fp=int(cmd.get("FP",0)); tn=int(cmd.get("TN",0)); fn=int(cmd.get("FN",0))
        ca, cb = st.columns([1, 1.2])
        with ca:
            fig = go.Figure(data=go.Heatmap(
                z=[[tp,fn],[fp,tn]], x=["Tah: Yukselis","Tah: Dusus"], y=["Ger: Yukselis","Ger: Dusus"],
                text=[[f"TP={tp}",f"FN={fn}"],[f"FP={fp}",f"TN={tn}"]],
                texttemplate="%{text}", textfont={"size":15,"color":"white"},
                colorscale=[[0,"#16213e"],[.5,"#533483"],[1,"#FF416C"]], showscale=False))
            fig.update_layout(template="plotly_dark",height=300,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',margin=dict(l=10,r=10,t=35,b=10),title="Confusion Matrix (N="+str(tp+fp+tn+fn)+")")
            st.plotly_chart(fig, use_container_width=True)
        with cb:
            st.dataframe(pd.DataFrame({
                "Metrik": ["Accuracy","Sensitivity","Specificity","Precision","F1","N"],
                "Deger": [f"{cmd.get('Accuracy',0):.4f}",f"{cmd.get('Sensitivity',0):.4f}",f"{cmd.get('Specificity',0):.4f}",f"{cmd.get('Precision',0):.4f}",f"{cmd.get('F1',0):.4f}",f"{int(cmd.get('N',0))}"],
                "Yorum": [f"Naive: {naive:.1%}" if arch is not None else "","Yukselis yakalama","Dusus yakalama","Tahmin kalitesi","Harmonik ort.","Tum foldlar"]
            }), use_container_width=True, hide_index=True)

    # Fold-level confusion
    cmf = L(S, "mcaware_pooled_confusion_by_fold.csv")
    if cmf is not None:
        st.markdown("### 📊 Fold Bazinda Confusion Matrix")
        st.dataframe(cmf, use_container_width=True, hide_index=True)

# ═══════════ TAB 2: MIMARI KARSILASTIRMA ═══════════
with tab2:
    st.markdown("### 🏗️ 7 DL Mimarisi — Tek Seferlik Test")
    st.caption("Her mimari 15 konfigurasyonla (3 lambda × 5 seed) test edildi")
    arch = L(S, "mcaware_multi_arch_CROSS_ARCH_SUMMARY.csv")
    if arch is not None:
        nv = float(arch["naive_acc"].iloc[0])
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Model Acc",x=arch["arch"],y=arch["mean_acc"],marker_color="#FF4444",text=[f"{v:.1%}" for v in arch["mean_acc"]],textposition="outside",textfont=dict(size=10,color="white")))
        fig.add_trace(go.Bar(name="Flip Acc",x=arch["arch"],y=arch["mean_acc_flip"],marker_color="#00CC66",text=[f"{v:.1%}" for v in arch["mean_acc_flip"]],textposition="outside",textfont=dict(size=10,color="white")))
        fig.add_hline(y=nv,line_dash="dash",line_color="#FFA500",line_width=2,annotation_text=f"Naive ({nv:.1%})")
        fig.update_layout(template="plotly_dark",barmode="group",height=420,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis_title="Accuracy",xaxis_title="Mimari",legend=dict(orientation="h",yanchor="bottom",y=1.02),yaxis=dict(range=[.3,.7]))
        st.plotly_chart(fig, use_container_width=True)
        finding("📌 Yorum","<b>Tum 7 mimaride</b> ayni oruntu: Model (kirmizi) naive altinda, flip (yesil) naive ustunde. Anti-prediktif davranis <b>mimariden bagimsiz</b>.")
        st.dataframe(arch.rename(columns={"arch":"Mimari","n_config":"Konfig","naive_acc":"Naive","mean_acc":"Model Acc","mean_acc_flip":"Flip Acc","flip_beats_naive_count":"Flip>Naive","mc_count":"MC"}), use_container_width=True, hide_index=True)

    # Walk-Forward Multi-Arch
    st.markdown("---")
    st.markdown("### 🏗️ Walk-Forward Multi-Arch (6 Mimari × 7 Fold)")
    wfma = L(S, "mcaware_walkforward_multi_arch_ARCH_SUMMARY.csv")
    if wfma is not None:
        st.dataframe(wfma.rename(columns={"arch":"Mimari","n_folds":"Fold","flip_beats_naive_n":"Flip>Naive","strict_anti_pred_n":"Strict Anti-Pred","mc_n":"MC","mean_acc":"Model Acc","mean_flip":"Flip Acc"}), use_container_width=True, hide_index=True)

    wfmr = L(S, "mcaware_walkforward_multi_arch_RESULTS.csv")
    if wfmr is not None:
        st.markdown("#### Fold × Mimari Detay (42 Sonuc)")
        fig_hm = go.Figure(data=go.Heatmap(
            z=wfmr.pivot(index="arch",columns="fold",values="Acc_flip").values,
            x=[f"Fold {i}" for i in sorted(wfmr["fold"].unique())],
            y=sorted(wfmr["arch"].unique()),
            colorscale=[[0,"#FF4444"],[.5,"#1a1a2e"],[1,"#00CC66"]],
            text=wfmr.pivot(index="arch",columns="fold",values="Acc_flip").applymap(lambda x:f"{x:.1%}").values,
            texttemplate="%{text}", showscale=True, colorbar_title="Flip Acc"
        ))
        fig_hm.update_layout(template="plotly_dark",height=300,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',title="Flip Accuracy Heatmap (Mimari × Fold)")
        st.plotly_chart(fig_hm, use_container_width=True)

# ═══════════ TAB 3: WALK-FORWARD ═══════════
with tab3:
    st.markdown("### 📈 Walk-Forward Cross Validation (7 Fold)")
    st.caption("Her fold 200 gun — model sadece gecmis veriyle egitildi")
    wf = L(S, "mcaware_walkforward_RESULTS.csv")
    if wf is not None:
        fig2 = go.Figure()
        fig2.add_trace(go.Scatter(x=wf["fold"],y=wf["acc"],mode="lines+markers",name="Model Acc",line=dict(color="#FF4444",width=3),marker=dict(size=10)))
        fig2.add_trace(go.Scatter(x=wf["fold"],y=wf["acc_flip"],mode="lines+markers",name="Flip Acc",line=dict(color="#00CC66",width=3),marker=dict(size=10)))
        fig2.add_trace(go.Scatter(x=wf["fold"],y=wf["naive_acc"],mode="lines+markers",name="Naive",line=dict(color="#FFA500",width=2,dash="dash"),marker=dict(size=7)))
        fig2.update_layout(template="plotly_dark",height=400,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',xaxis_title="Fold",yaxis_title="Accuracy",xaxis=dict(dtick=1),legend=dict(orientation="h",yanchor="bottom",y=1.02),yaxis=dict(range=[.35,.75]))
        st.plotly_chart(fig2, use_container_width=True)
        ws = wf[["fold","n_train","n_test","up_pct_test","naive_acc","acc","acc_flip","flip_beats_naive","sens","spec"]].copy()
        ws.columns = ["Fold","Egitim N","Test N","Yukselis %","Naive","Model Acc","Flip Acc","Flip Kazanir?","Sens","Spec"]
        for c in ["Yukselis %","Naive","Model Acc","Flip Acc","Sens","Spec"]: ws[c] = ws[c].apply(lambda x: f"{x:.3f}")
        st.dataframe(ws, use_container_width=True, hide_index=True)

    # WF fold summary (multi arch)
    wff = L(S, "mcaware_walkforward_multi_arch_FOLD_SUMMARY.csv")
    if wff is not None:
        st.markdown("### Walk-Forward Fold Ozeti (6 Mimari Ortalamasi)")
        st.dataframe(wff, use_container_width=True, hide_index=True)

# ═══════════ TAB 4: TAHMIN ANALIZI ═══════════
with tab4:
    st.markdown("### 🔍 Varliga Ozel Gercek Tahmin Sonuclari")
    PM = {
        "BIST: THYAO (Havacilik)": ("mcaware_BiLSTM_v3THYAO_PREDICTIONS.csv","stock"),
        "BIST: GARAN (Bankacilik)": ("mcaware_BiLSTM_v3b_GARAN_PREDICTIONS.csv","stock"),
        "BES: AMZ (Hisse Fonu)": ("mcaware_BiLSTM_v3b_BES_AMZ_PREDICTIONS.csv","bes"),
        "BES: AZS (Esnek Fon)": ("mcaware_BiLSTM_v3b_BES_AZS_PREDICTIONS.csv","bes"),
        "BES: ALZ (Dusuk Risk)": ("mcaware_BiLSTM_v3b_BES_ALZ_PREDICTIONS.csv","bes"),
    }
    sel = st.selectbox("Varlik:", list(PM.keys()))
    fn, vt = PM[sel]
    df = L(P, fn)
    if df is not None:
        seeds = sorted(df["seed"].unique()); lambdas = sorted(df["lambda"].unique())
        lc,sc = st.columns(2)
        with lc: sl = st.selectbox("Lambda:", lambdas, index=0)
        with sc: ss = st.selectbox("Seed:", seeds, index=0)
        sub = df[(df["seed"]==ss)&(df["lambda"]==sl)].copy() if vt=="bes" else df[(df["set"]=="test")&(df["seed"]==ss)&(df["lambda"]==sl)].copy()
        if len(sub)>0:
            sub = sub.reset_index(drop=True)
            sub["pred"]=(sub["yhat"]>.5).astype(int); sub["pf"]=1-sub["pred"]
            sub["c"]=(sub["pred"]==sub["y_true"]).astype(int); sub["cf"]=(sub["pf"]==sub["y_true"]).astype(int)
            acc=sub["c"].mean(); af=sub["cf"].mean(); nv=max(sub["y_true"].mean(),1-sub["y_true"].mean())
            m1,m2,m3,m4=st.columns(4)
            with m1: st.metric("Test N",f"{len(sub)}")
            with m2: st.metric("Model Acc",f"{acc:.1%}")
            with m3: st.metric("Flip Acc",f"{af:.1%}",delta=f"{(af-acc)*100:+.1f}pp")
            with m4: st.metric("Naive",f"{nv:.1%}")
            # Histogram
            fig3=go.Figure()
            fig3.add_trace(go.Histogram(x=sub[sub["y_true"]==1]["yhat"],name="Yukselis",marker_color="#00CC66",opacity=.7,nbinsx=25))
            fig3.add_trace(go.Histogram(x=sub[sub["y_true"]==0]["yhat"],name="Dusus",marker_color="#FF4444",opacity=.7,nbinsx=25))
            fig3.add_vline(x=.5,line_dash="dash",line_color="white",annotation_text="Esik=0.5")
            fig3.update_layout(template="plotly_dark",barmode="overlay",height=300,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',xaxis_title="yhat",yaxis_title="Frekans")
            st.plotly_chart(fig3, use_container_width=True)
            # Confusion
            tp=int(((sub["pred"]==1)&(sub["y_true"]==1)).sum()); fp=int(((sub["pred"]==1)&(sub["y_true"]==0)).sum())
            tn=int(((sub["pred"]==0)&(sub["y_true"]==0)).sum()); fn2=int(((sub["pred"]==0)&(sub["y_true"]==1)).sum())
            ca2,cb2=st.columns([1,1.2])
            with ca2:
                fcm=go.Figure(data=go.Heatmap(z=[[tp,fn2],[fp,tn]],x=["Tah:Yuk","Tah:Dus"],y=["Ger:Yuk","Ger:Dus"],text=[[f"TP={tp}",f"FN={fn2}"],[f"FP={fp}",f"TN={tn}"]],texttemplate="%{text}",textfont={"size":14,"color":"white"},colorscale=[[0,"#16213e"],[1,"#FF416C"]],showscale=False))
                fcm.update_layout(template="plotly_dark",height=270,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',margin=dict(l=10,r=10,t=30,b=10))
                st.plotly_chart(fcm, use_container_width=True)
            with cb2:
                sn=tp/(tp+fn2) if(tp+fn2)>0 else 0; sp=tn/(tn+fp) if(tn+fp)>0 else 0; pr=tp/(tp+fp) if(tp+fp)>0 else 0; f1=2*pr*sn/(pr+sn) if(pr+sn)>0 else 0
                st.dataframe(pd.DataFrame({"Metrik":["Accuracy","Sensitivity","Specificity","Precision","F1"],"Deger":[f"{acc:.4f}",f"{sn:.4f}",f"{sp:.4f}",f"{pr:.4f}",f"{f1:.4f}"]}),use_container_width=True,hide_index=True)
            # Cumulative
            sub["ca"]=sub["c"].expanding().mean(); sub["caf"]=sub["cf"].expanding().mean(); sub["idx"]=range(len(sub))
            fig4=go.Figure()
            fig4.add_trace(go.Scatter(x=sub["idx"],y=sub["ca"],name="Model",line=dict(color="#FF4444",width=2)))
            fig4.add_trace(go.Scatter(x=sub["idx"],y=sub["caf"],name="Flipped",line=dict(color="#00CC66",width=2)))
            fig4.add_hline(y=nv,line_dash="dash",line_color="#FFA500",annotation_text=f"Naive ({nv:.1%})")
            fig4.update_layout(template="plotly_dark",height=270,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',xaxis_title="Test #",yaxis_title="Kum. Accuracy")
            st.plotly_chart(fig4, use_container_width=True)

    # BES Cross-Fund
    st.markdown("---")
    st.markdown("### 📊 BES Fonlari Karsilastirmasi")
    bf = L(S, "mcaware_BiLSTM_v3b_BES_CROSS_FUND_SUMMARY.csv")
    if bf is not None:
        st.dataframe(bf.rename(columns={"fund":"Fon","n_config":"Konfig","naive_acc":"Naive","mean_acc":"Model Acc","mean_acc_flip":"Flip Acc","flip_beats_naive_count":"Flip>Naive","mc_count":"MC","is_degenerate":"Dejenere?"}), use_container_width=True, hide_index=True)
        finding("📌 BES Fonlari","ALZ (dusuk risk) dejenere — tum gunler ayni yon. AMZ ve AZS'de anti-prediktif davranis <b>gorulmuyor</b> — BES fonlari BIST hisselerinden farkli davranis sergiliyor.")

# ═══════════ TAB 5: ABLATION ═══════════
with tab5:
    st.markdown("### 🧪 Feature Ablation Deneyleri")

    # Feature group ablation
    fa = L(S, "mcaware_feature_ablation_SUMMARY.csv")
    if fa is not None:
        st.markdown("#### Harici Degisken Grubu Ablation")
        st.caption("13 ozellik (full) vs 10 ozellik (harici degiskenler cikarildi)")
        fig_fa=go.Figure()
        fig_fa.add_trace(go.Bar(name="Model Acc",x=fa["group"],y=fa["mean_acc"],marker_color="#FF4444",text=[f"{v:.1%}" for v in fa["mean_acc"]],textposition="outside"))
        fig_fa.add_trace(go.Bar(name="Flip Acc",x=fa["group"],y=fa["mean_flip"],marker_color="#00CC66",text=[f"{v:.1%}" for v in fa["mean_flip"]],textposition="outside"))
        fig_fa.add_hline(y=float(fa["naive"].iloc[0]),line_dash="dash",line_color="#FFA500",annotation_text=f"Naive ({fa['naive'].iloc[0]:.1%})")
        fig_fa.update_layout(template="plotly_dark",barmode="group",height=350,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis=dict(range=[.3,.7]))
        st.plotly_chart(fig_fa, use_container_width=True)
        finding("⚡ Kritik Bulgu","13 ozellik ile %60 flip acc (anti-prediktif). Harici degiskenler cikarildiginda flip acc %50'ye duser. <b>Harici makro degiskenler anti-prediktif davranisi tetikliyor.</b>")

    # Single feature ablation
    sf = L(S, "mcaware_single_feat_ablation_SUMMARY.csv")
    if sf is not None:
        st.markdown("---")
        st.markdown("#### Tek Tek Ozellik Cikarma")
        st.caption("Her seferinde tek bir harici degisken cikarildi")
        fig_sf=go.Figure()
        fig_sf.add_trace(go.Bar(name="Model Acc",x=sf["group"],y=sf["mean_acc"],marker_color="#FF4444",text=[f"{v:.1%}" for v in sf["mean_acc"]],textposition="outside"))
        fig_sf.add_trace(go.Bar(name="Flip Acc",x=sf["group"],y=sf["mean_flip"],marker_color="#00CC66",text=[f"{v:.1%}" for v in sf["mean_flip"]],textposition="outside"))
        fig_sf.update_layout(template="plotly_dark",barmode="group",height=350,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis=dict(range=[.3,.7]))
        st.plotly_chart(fig_sf, use_container_width=True)
        st.dataframe(sf.rename(columns={"group":"Grup","n_feat":"Ozellik N","n_seed":"Seed","mean_acc":"Model Acc","mean_flip":"Flip Acc","flip_wins":"Flip Kazanir"}), use_container_width=True, hide_index=True)
        finding("📌 Yorum","Tek degisken cikarma anti-prediktif davranisi <b>tamamen ortadan kaldirmiyor</b>. 3 harici degiskenin <b>hepsini birden</b> cikarmak gerekiyor — bu da etkilesim (interaction) etkisine isaret ediyor.")

    # Input length ablation
    il = L(S, "mcaware_inlen_ablation_SUMMARY.csv")
    if il is not None:
        st.markdown("---")
        st.markdown("#### Gecmis Pencere Boyutu (IN_LEN) Ablation")
        fig_il=go.Figure()
        fig_il.add_trace(go.Bar(name="Model Acc",x=il["IN_LEN"].astype(str),y=il["mean_acc"],marker_color="#FF4444",text=[f"{v:.1%}" for v in il["mean_acc"]],textposition="outside"))
        fig_il.add_trace(go.Bar(name="Flip Acc",x=il["IN_LEN"].astype(str),y=il["mean_flip"],marker_color="#00CC66",text=[f"{v:.1%}" for v in il["mean_flip"]],textposition="outside"))
        fig_il.update_layout(template="plotly_dark",barmode="group",height=320,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',xaxis_title="Pencere (gun)",yaxis=dict(range=[.4,.6]))
        st.plotly_chart(fig_il, use_container_width=True)
        st.dataframe(il.rename(columns={"IN_LEN":"Pencere","n":"Konfig","naive":"Naive","mean_acc":"Model Acc","mean_flip":"Flip Acc","flip_beats_naive_n":"Flip>Naive","strict_anti_pred_n":"Strict Anti","mc_n":"MC"}), use_container_width=True, hide_index=True)

# ═══════════ TAB 6: CROSS-MARKET ═══════════
with tab6:
    st.markdown("### 🌍 Cross-Market Analizi: BIST vs NASDAQ")
    nq = L(S, "mcaware_nasdaq_SUMMARY.csv")
    if nq is not None:
        fig_nq=go.Figure()
        fig_nq.add_trace(go.Bar(name="Model Acc",x=nq["market"]+" ("+nq["group"]+")",y=nq["mean_acc"],marker_color="#FF4444",text=[f"{v:.1%}" for v in nq["mean_acc"]],textposition="outside"))
        fig_nq.add_trace(go.Bar(name="Flip Acc",x=nq["market"]+" ("+nq["group"]+")",y=nq["mean_flip"],marker_color="#00CC66",text=[f"{v:.1%}" for v in nq["mean_flip"]],textposition="outside"))
        fig_nq.add_hline(y=.5,line_dash="dash",line_color="#FFA500")
        fig_nq.update_layout(template="plotly_dark",barmode="group",height=400,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis=dict(range=[.3,.7]),yaxis_title="Accuracy")
        st.plotly_chart(fig_nq, use_container_width=True)
        st.dataframe(nq.rename(columns={"market":"Piyasa","group":"Ozellik Grubu","n_feat":"Ozellik N","n":"Seed","mean_acc":"Model Acc","mean_flip":"Flip Acc","flip_wins":"Flip Kazanir"}), use_container_width=True, hide_index=True)
        finding("🌍 Cross-Market Bulgu",
            "<b>BIST THYAO</b>: Anti-prediktif davranis belirgin (%60 flip acc).<br>"
            "<b>NASDAQ AAPL</b>: Anti-prediktif davranis <b>YOK</b> — model %52 ile naive'e yakin.<br><br>"
            "Bu, anti-prediktif davransin <b>piyasaya ozgu</b> oldugunu gosteriyor. "
            "Gelismekte olan piyasalarda (BIST) makro degiskenler farkli bir sinyal yaratiyor.")

    # Multi-stock (3 BIST)
    st.markdown("---")
    st.markdown("### 📊 Coklu BIST Hissesi (Bankacilik)")
    ms = L(S, "mcaware_bist_multi_stock_SUMMARY.csv")
    if ms is not None:
        st.dataframe(ms.rename(columns={"ticker":"Hisse","n_seeds":"Seed","mean_acc":"Model Acc","mean_flip":"Flip Acc","flip_wins":"Flip Kazanir","mc_count":"MC","naive":"Naive"}), use_container_width=True, hide_index=True)

    # Holding + Sigorta
    st.markdown("---")
    ch,cs = st.columns(2)
    with ch:
        st.markdown("### 🏦 Holding Sektoru (5 hisse)")
        h = L(S, "mcaware_bist5_holding_SUMMARY.csv")
        if h is not None:
            hs = h[["ticker","mean_acc","mean_flip","naive"]].copy()
            hs.columns = ["Hisse","Model Acc","Flip Acc","Naive"]
            for c in ["Model Acc","Flip Acc","Naive"]: hs[c]=hs[c].apply(lambda x:f"{x:.3f}")
            st.dataframe(hs, use_container_width=True, hide_index=True)
    with cs:
        st.markdown("### 🛡️ Sigorta Sektoru (5 hisse)")
        s = L(S, "mcaware_bist5_sigorta_SUMMARY.csv")
        if s is not None:
            ss2 = s[["ticker","mean_acc","mean_flip","naive","dl_anti_prediktif_mi"]].copy()
            ss2.columns = ["Hisse","Model Acc","Flip Acc","Naive","Anti-Pred?"]
            for c in ["Model Acc","Flip Acc","Naive"]: ss2[c]=ss2[c].apply(lambda x:f"{x:.3f}")
            st.dataframe(ss2, use_container_width=True, hide_index=True)

    # Sigorta V2 (genisletilmis)
    sv2 = L(S, "mcaware_bist5_sigorta_v2_SUMMARY.csv")
    if sv2 is not None:
        st.markdown("### 🛡️ Sigorta V2 (Genisletilmis)")
        st.dataframe(sv2, use_container_width=True, hide_index=True)

# ═══════════ TAB 7: ENSEMBLE & BASELINE ═══════════
with tab7:
    st.markdown("### 🗳️ Ensemble Voting & Rule-Based Baseline")

    # Ensemble
    ens = L(S, "mcaware_ensemble_RESULTS.csv")
    if ens is not None:
        st.markdown("#### Ensemble Voting (6 Mimari)")
        st.caption("6 mimarinin tahminleri hard/soft voting ile birlestirildi")
        fig_e=go.Figure()
        fig_e.add_trace(go.Bar(name="Model Acc",x=ens["name"],y=ens["Acc"],marker_color="#FF4444",text=[f"{v:.1%}" for v in ens["Acc"]],textposition="outside"))
        fig_e.add_trace(go.Bar(name="Flip Acc",x=ens["name"],y=ens["Acc_flip"],marker_color="#00CC66",text=[f"{v:.1%}" for v in ens["Acc_flip"]],textposition="outside"))
        fig_e.update_layout(template="plotly_dark",barmode="group",height=400,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis=dict(range=[.3,.7]),xaxis_title="Model / Ensemble")
        st.plotly_chart(fig_e, use_container_width=True)
        st.dataframe(ens.rename(columns={"name":"Model","Acc":"Accuracy","Sens":"Sensitivity","Spec":"Specificity","Acc_flip":"Flip Acc","flip_beats_naive":"Flip>Naive","type":"Tur"}), use_container_width=True, hide_index=True)
        finding("📌 Ensemble Sonucu","Ensemble bile anti-prediktif — <b>hard vote %60</b>, <b>soft vote %62</b> flip acc. 6 mimarinin hatalari <b>bagımsız degil, sistematik</b>.")

    # Rule-based baseline
    st.markdown("---")
    st.markdown("#### 📏 Rule-Based ML Baseline (THYAO)")
    st.caption("Klasik ML modelleri vs DL — ayni veri")
    rb = L(S, "mcaware_rule_based_RESULTS.csv")
    if rb is not None:
        fig_rb=go.Figure()
        fig_rb.add_trace(go.Bar(name="Model Acc",x=rb["model"],y=rb["Acc"],marker_color="#4488FF",text=[f"{v:.1%}" for v in rb["Acc"]],textposition="outside"))
        fig_rb.add_trace(go.Bar(name="Flip Acc",x=rb["model"],y=rb["Acc_flip"],marker_color="#FF8844",text=[f"{v:.1%}" for v in rb["Acc_flip"]],textposition="outside"))
        fig_rb.update_layout(template="plotly_dark",barmode="group",height=350,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis=dict(range=[.3,.65]))
        st.plotly_chart(fig_rb, use_container_width=True)
        st.dataframe(rb, use_container_width=True, hide_index=True)
        finding("📌 Klasik ML","DT, OneR, RF, LR — hicbiri anti-prediktif degil. Anti-prediktif davranis <b>sadece derin ogrenme modellerinde</b> ortaya cikiyor.")

    # AAPL rule-based
    rba = L(S, "mcaware_rule_based_AAPL_RESULTS.csv")
    if rba is not None:
        st.markdown("#### NASDAQ AAPL — Rule-Based")
        st.dataframe(rba, use_container_width=True, hide_index=True)

    # GARAN rule-based
    rbg = L(S, "mcaware_rule_based_GARAN_RESULTS.csv")
    if rbg is not None:
        st.markdown("#### BIST GARAN — Rule-Based")
        st.dataframe(rbg, use_container_width=True, hide_index=True)

    # Majority Rules (10 indikatör)
    st.markdown("---")
    st.markdown("#### 📊 Teknik Analiz Indikatorleri (10 Kural)")
    st.caption("SMA, EMA, RSI, MACD, Bollinger, Stoch, CCI, WilliamsR, ADX, ROC")
    mr = L(S, "mcaware_majority_rules_10ind_SUMMARY.csv")
    if mr is not None:
        fig_mr=go.Figure()
        fig_mr.add_trace(go.Bar(x=mr["method"],y=mr["accuracy"],marker_color=["#00CC66" if b else "#FF4444" for b in mr["beats_naive"]],text=[f"{v:.1%}" for v in mr["accuracy"]],textposition="outside"))
        fig_mr.add_hline(y=float(mr["naive_acc"].iloc[0]),line_dash="dash",line_color="#FFA500",annotation_text=f"Naive ({mr['naive_acc'].iloc[0]:.1%})")
        fig_mr.update_layout(template="plotly_dark",height=380,paper_bgcolor='rgba(0,0,0,0)',plot_bgcolor='rgba(0,0,0,0)',yaxis_title="Accuracy",xaxis_title="Indikatör",yaxis=dict(range=[.4,1.0]))
        st.plotly_chart(fig_mr, use_container_width=True)
        st.dataframe(mr.rename(columns={"method":"Yontem","accuracy":"Accuracy","naive_acc":"Naive","beats_naive":"Naive'i Gecer?","up_signal_ratio":"Yukselis Sinyal %"}), use_container_width=True, hide_index=True)
        finding("📌 Teknik Analiz","SMA Cross %87 ile en basarili. Ama bu <b>geleceğe bakan (look-ahead)</b> bir sinyal — gercek ticarette bu performans elde edilemez. DL modelleri ise sadece gecmis veriye bakiyor.")

# ─── SIDEBAR ───
with st.sidebar:
    st.markdown("## 📖 Proje Bilgisi")
    st.markdown("""
    **MC-AWARE**
    *Multi-Class Aware Deep Learning
    for Financial Direction Prediction*

    ---
    **Destek:** TUBiTAK 2209-A
    **Yurutucu:** Mehmet Ali Kurt
    **Danisman:** Dr. Ovgucan Karadag Erdemir
    **Uni:** Hacettepe — Aktuerya

    ---
    **6 DL Mimarisi:**
    BiLSTM · GRU · Conv1D
    TCN · Transformer · SimpleRNN

    ---
    **Veri Kaynaklari:**
    - BIST gunluk kapanis (16 hisse)
    - BES fon fiyatlari (3 fon)
    - NASDAQ AAPL (cross-market)
    - Makro: USD/TRY, Faiz, Petrol, Altin

    ---
    **Deney Serileri:**
    - 350+ konfigurasyon testi
    - 7-fold walk-forward CV
    - Feature & input ablation
    - Cross-market dogrulama
    - 10 teknik indikatör
    - Ensemble voting
    - Rule-based baseline

    ---
    *Tum sonuclar gercek deney
    CSV dosyalarindan yuklenir.
    Yatirim tavsiyesi degildir.*
    """)

# ─── FOOTER ───
st.markdown("---")
st.markdown("""<div style="text-align:center;color:#555;font-size:.85rem;padding:10px;">
MC-AWARE | TUBiTAK 2209-A | 2026 | Mehmet Ali Kurt | Dr. Ovgucan Karadag Erdemir | Hacettepe Uni.<br>
<i>Tum grafikler ve tablolar Sonuclar/ klasorundeki gercek CSV dosyalarindan yuklenmektedir.</i>
</div>""", unsafe_allow_html=True)

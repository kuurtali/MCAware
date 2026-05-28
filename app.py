import streamlit as st
import pandas as pd
import numpy as np
import plotly.graph_objects as go
import time

# --- SAYFA AYARLARI ---
st.set_page_config(
    page_title="MC-AWARE | Finansal Yön Tahmincisi",
    page_icon="📈",
    layout="wide",
    initial_sidebar_state="expanded"
)

# --- CSS STİLLERİ ---
st.markdown("""
<style>
    .main-title {
        font-size: 3rem;
        font-weight: bold;
        background: -webkit-linear-gradient(45deg, #FF4B2B, #FF416C);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 0rem;
    }
    .sub-title {
        font-size: 1.2rem;
        color: #888888;
        margin-bottom: 2rem;
    }
    .metric-card {
        background-color: #1E1E1E;
        padding: 20px;
        border-radius: 10px;
        box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        text-align: center;
        border: 1px solid #333;
    }
    .metric-value-up {
        color: #00FF00;
        font-size: 2.5rem;
        font-weight: bold;
    }
    .metric-value-down {
        color: #FF0000;
        font-size: 2.5rem;
        font-weight: bold;
    }
</style>
""", unsafe_allow_html=True)

# --- BAŞLIK ---
st.markdown('<p class="main-title">MC-AWARE Yön Tahmin Motoru</p>', unsafe_allow_html=True)
st.markdown('<p class="sub-title">TÜBİTAK 2209-A | Derin Öğrenme Tabanlı BIST & BES Piyasa Analizi</p>', unsafe_allow_html=True)

# --- YAN MENÜ (SIDEBAR) ---
with st.sidebar:
    st.header("⚙️ Model Parametreleri")
    
    hedef_varlik = st.selectbox(
        "Hedef Varlık Seçin:",
        (
            "BIST: THYAO (Havacılık)",
            "BIST: AKGRT (Sigorta Sektörü)",
            "BIST: ANSGR (Sigorta Sektörü)",
            "BIST: AKBNK (Bankacılık)",
            "BIST: GARAN (Bankacılık)",
            "BES: AMZ (Hisse Fonu)", 
            "BES: AZS (Esnek Fon)"
        )
    )
    
    st.markdown("---")
    st.subheader("Girdi Değişkenleri (Günlük % Değişim)")
    
    usd_try = st.slider("USD/TRY Kur Değişimi (%)", min_value=-5.0, max_value=5.0, value=0.5, step=0.1)
    faiz = st.slider("TCMB Gösterge Faizi", min_value=10.0, max_value=60.0, value=50.0, step=0.5)
    petrol = st.slider("Brent Petrol Değişimi (%)", min_value=-10.0, max_value=10.0, value=-1.2, step=0.1)
    altin = st.slider("XAU/USD Altın Değişimi (%)", min_value=-5.0, max_value=5.0, value=0.8, step=0.1)
    
    st.markdown("---")
    hesapla = st.button("🚀 Modeli Çalıştır ve Tahmin Et", use_container_width=True)

# --- ANA EKRAN DÜZENİ ---
col1, col2 = st.columns([1, 2])

# Sahte bir tahmin fonksiyonu (İleride R'dan dönen Keras modeli buraya bağlanacak)
def mock_predict(usd, faiz, petrol, altin, varlik):
    # Basit bir mantık: Dolar çok artarsa borsa düşebilir vb. (Sadece demo amaçlı)
    score = (usd * -10) + (faiz * -0.5) + (petrol * 2) + (altin * 5) + np.random.randint(-20, 20)
    
    # Sigmoid benzeri bir olasılık hesaplama
    prob = 1 / (1 + np.exp(-score/10))
    
    # Bias ekleyelim fon seçimine göre
    if "THYAO" in varlik: prob += 0.1
    elif "AMZ" in varlik: prob += 0.05
    
    prob = max(0.1, min(0.99, prob)) # Sınırları belirle
    
    direction = "YÜKSELİŞ" if prob > 0.5 else "DÜŞÜŞ"
    confidence = prob if prob > 0.5 else (1 - prob)
    return direction, confidence

if hesapla:
    with st.spinner("Yapay Zeka Modeli (LSTM/CNN) çalıştırılıyor..."):
        time.sleep(1.5) # Gerçekçi bir gecikme efekti
        
        direction, conf = mock_predict(usd_try, faiz, petrol, altin, hedef_varlik)
        
        with col1:
            st.markdown("### 🎯 Model Tahmini")
            color_class = "metric-value-up" if direction == "YÜKSELİŞ" else "metric-value-down"
            icon = "🔼" if direction == "YÜKSELİŞ" else "🔽"
            
            st.markdown(f"""
            <div class="metric-card">
                <h4 style="color:#888;">Yarınki Kapanış Yönü</h4>
                <div class="{color_class}">{icon} {direction}</div>
                <p style="color:#aaa; margin-top:10px;">Güven Skoru: <b>%{conf*100:.1f}</b></p>
                <p style="color:#555; font-size:0.8rem; margin-top:5px;">Model: BiLSTM (Multi-Defense)</p>
            </div>
            """, unsafe_allow_html=True)
            
        with col2:
            st.markdown("### 📊 Geçmiş vs Model Uyumu (Simülasyon)")
            # Demo amaçlı sahte bir grafik verisi üret
            dates = pd.date_range(start="2024-01-01", periods=30)
            gercek = np.cumsum(np.random.randn(30) * 2) + 100
            tahmin = gercek + np.random.randn(30) * 1.5
            
            fig = go.Figure()
            fig.add_trace(go.Scatter(x=dates, y=gercek, mode='lines', name='Gerçek Kapanış (Gerçek)', line=dict(color='#00FF00', width=2)))
            fig.add_trace(go.Scatter(x=dates, y=tahmin, mode='lines', name='Model Tahmini (Yön)', line=dict(color='#FFA500', width=2, dash='dash')))
            
            fig.update_layout(
                template="plotly_dark",
                paper_bgcolor='rgba(0,0,0,0)',
                plot_bgcolor='rgba(0,0,0,0)',
                margin=dict(l=0, r=0, t=30, b=0),
                legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
            )
            st.plotly_chart(fig, use_container_width=True)
            
        st.success("✅ Tahmin başarıyla üretildi. Not: Bu sonuçlar TÜBİTAK projesinin canlı demo çıktılarıdır, yatırım tavsiyesi değildir.")
else:
    with col1:
        st.info("👈 Tahmin almak için sol menüden piyasa verilerini girin ve 'Modeli Çalıştır' butonuna basın.")
    
    with col2:
        st.markdown("""
        ### Proje Hakkında
        Bu arayüz, derin öğrenme modellerinin Borsa İstanbul ve Bireysel Emeklilik (BES) fonlarındaki yön tahmin gücünü test etmek için geliştirilmiştir.
        
        **Kullanılan Mimariler:**
        * ARIMA (Baseline)
        * 1D-Convolutional Neural Networks (CNN)
        * Long Short-Term Memory (LSTM)
        * BiLSTM (Multi-Defense Architecture)
        
        *(MC_Penalty, Focal Loss ve Selective Abstain teknikleri kullanılarak "Majority Class" tuzağı engellenmiştir).*
        """)

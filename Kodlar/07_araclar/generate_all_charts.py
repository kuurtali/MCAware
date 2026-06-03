"""
MC-AWARE: 15 Yeni Gorsel Uretici
CSV verilerinden akademik kalitede grafikler
"""
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
import numpy as np
import os, warnings
warnings.filterwarnings('ignore')

matplotlib.rcParams['font.family'] = 'DejaVu Sans'
matplotlib.rcParams['axes.unicode_minus'] = False

BASE = r'C:\Users\Kurt\Desktop\Tubitak\Sonuclar'
OUT = r'C:\Users\Kurt\Desktop\Tubitak\Gorseller'
DPI = 300

# Renkler
C_BLUE = '#1B3A5C'
C_ORANGE = '#E67E22'
C_GREEN = '#27AE60'
C_RED = '#E74C3C'
C_GRAY = '#95A5A6'
C_PURPLE = '#8E44AD'
C_TEAL = '#16A085'

generated = []

# ============================================================
# CHART 1: 11 BIST Per-Stock Accuracy Bar
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_bist_ALL_macro_SUMMARY.csv'), encoding='utf-8-sig')
    print(f'Chart 1: {len(df)} stocks loaded, cols: {list(df.columns)[:8]}')
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Detect column names
    ticker_col = [c for c in df.columns if 'ticker' in c.lower()][0]
    naive_col = [c for c in df.columns if 'naive' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() in ['acc_05', 'acc', 'mean_acc']][0] if 'Acc_05' in df.columns else df.columns[4]
    flip_col = [c for c in df.columns if 'flip' in c.lower() and 'acc' in c.lower()][0]
    
    x = np.arange(len(df))
    w = 0.25
    
    bars1 = ax.bar(x - w, df[naive_col]*100 if df[naive_col].max() <= 1 else df[naive_col], w, label='Naive (%)', color=C_GRAY, alpha=0.8)
    bars2 = ax.bar(x, df[acc_col]*100 if df[acc_col].max() <= 1 else df[acc_col], w, label='Model (%)', color=C_RED, alpha=0.8)
    bars3 = ax.bar(x + w, df[flip_col]*100 if df[flip_col].max() <= 1 else df[flip_col], w, label='Flip (%)', color=C_GREEN, alpha=0.8)
    
    ax.set_xlabel('Hisse', fontsize=11, fontweight='bold')
    ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
    ax.set_title('11 BIST Hissesi: Doğruluk Karşılaştırması', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.set_xticks(x)
    ax.set_xticklabels(df[ticker_col], rotation=45, ha='right', fontsize=9)
    ax.legend(fontsize=9)
    ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5, label='Rastgele (%50)')
    ax.set_ylim(30, 70)
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '34_PerStock_AccBar_11BIST.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('34_PerStock_AccBar_11BIST.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 1 HATA: {e}')

# ============================================================
# CHART 2: Threshold Optimization Heatmap
# ============================================================
try:
    thr_files = [f for f in os.listdir(os.path.join(BASE, 'thresholds')) if f.endswith('.csv')]
    print(f'Chart 2: {len(thr_files)} threshold files')
    
    # Use first available
    df = pd.read_csv(os.path.join(BASE, 'thresholds', thr_files[0]), encoding='utf-8-sig')
    print(f'  Cols: {list(df.columns)[:10]}')
    
    lam_col = [c for c in df.columns if 'lambda' in c.lower() or 'lam' in c.lower()][0]
    thr_col = [c for c in df.columns if 'threshold' in c.lower() or 'thr' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc' or c.lower() == 'accuracy'][0]
    
    pivot = df.groupby([thr_col, lam_col])[acc_col].mean().reset_index()
    pivot_table = pivot.pivot(index=thr_col, columns=lam_col, values=acc_col)
    
    fig, ax = plt.subplots(figsize=(10, 8))
    im = ax.imshow(pivot_table.values, cmap='RdYlGn', aspect='auto', vmin=0.35, vmax=0.60)
    
    ax.set_xticks(range(len(pivot_table.columns)))
    ax.set_xticklabels([f'{v:.2f}' for v in pivot_table.columns], fontsize=8)
    ax.set_yticks(range(len(pivot_table.index)))
    ax.set_yticklabels([f'{v:.2f}' for v in pivot_table.index], fontsize=8)
    
    ax.set_xlabel('Lambda (λ)', fontsize=11, fontweight='bold')
    ax.set_ylabel('Eşik (Threshold)', fontsize=11, fontweight='bold')
    ax.set_title('Eşik Optimizasyonu Yüzey Haritası', fontsize=14, fontweight='bold', color=C_BLUE)
    
    plt.colorbar(im, ax=ax, label='Doğruluk (Acc)')
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '35_Threshold_Heatmap.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('35_Threshold_Heatmap.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 2 HATA: {e}')

# ============================================================
# CHART 3: MI Scores Bar
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'diagnostics', 'mcaware_v4_MI_SCORES.csv'), encoding='utf-8-sig')
    print(f'Chart 3: MI scores, cols: {list(df.columns)}')
    
    mi_col = [c for c in df.columns if 'MI' in c and 'bit' in c.lower()][0] if any('bit' in c.lower() for c in df.columns) else [c for c in df.columns if 'MI' in c][0]
    ds_col = [c for c in df.columns if 'dataset' in c.lower() or 'name' in c.lower()][0]
    
    fig, ax = plt.subplots(figsize=(10, 6))
    colors = [C_BLUE if v > 0.01 else C_RED for v in df[mi_col]]
    bars = ax.barh(df[ds_col], df[mi_col], color=colors, alpha=0.85, edgecolor='white')
    
    ax.set_xlabel('Karşılıklı Bilgi (MI) - bit', fontsize=11, fontweight='bold')
    ax.set_title('Karşılıklı Bilgi (MI) Skorları', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.grid(axis='x', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '36_MI_Scores_Bar.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('36_MI_Scores_Bar.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 3 HATA: {e}')

# ============================================================
# CHART 4: Ensemble Agreement
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'predictions', 'mcaware_ensemble_HARD_VOTES.csv'), encoding='utf-8-sig')
    print(f'Chart 4: Ensemble votes, cols: {list(df.columns)[:8]}')
    
    vote_col = [c for c in df.columns if 'vote' in c.lower() and 'n' in c.lower()][0] if any('vote' in c.lower() for c in df.columns) else None
    ytrue_col = [c for c in df.columns if 'true' in c.lower() or 'actual' in c.lower()][0]
    
    if vote_col:
        n_arch = df[vote_col].max()
        df['agreement'] = (df[vote_col] == n_arch) | (df[vote_col] == 0)
        agree_acc = (df[df['agreement']][ytrue_col] == (df[df['agreement']][vote_col] > n_arch/2).astype(int)).mean()
        disagree_acc = (df[~df['agreement']][ytrue_col] == (df[~df['agreement']][vote_col] > n_arch/2).astype(int)).mean()
        agree_pct = df['agreement'].mean() * 100
        
        fig, ax = plt.subplots(figsize=(8, 6))
        bars = ax.bar(['Uzlaşma\n(Tüm modeller hemfikir)', 'Uyuşmazlık\n(Modeller bölünmüş)'],
                      [agree_acc*100, disagree_acc*100],
                      color=[C_GREEN, C_RED], alpha=0.85, width=0.5)
        
        for bar, val in zip(bars, [agree_acc*100, disagree_acc*100]):
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
                    f'%{val:.1f}', ha='center', fontsize=12, fontweight='bold')
        
        ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
        ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
        ax.set_title(f'Ensemble Uzlaşma Analizi\n(Uzlaşma oranı: %{agree_pct:.0f})', 
                     fontsize=14, fontweight='bold', color=C_BLUE)
        ax.set_ylim(30, 70)
        ax.grid(axis='y', alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(os.path.join(OUT, '37_Ensemble_Agreement.png'), dpi=DPI, bbox_inches='tight')
        plt.close()
        generated.append('37_Ensemble_Agreement.png')
        print('  -> OK')
except Exception as e:
    print(f'  Chart 4 HATA: {e}')

# ============================================================
# CHART 5: Cross-Market Feature Ablation
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_nasdaq_RESULTS.csv'), encoding='utf-8-sig')
    print(f'Chart 5: NASDAQ, cols: {list(df.columns)[:8]}')
    
    grp_col = [c for c in df.columns if 'group' in c.lower() or 'market' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
    flip_col = [c for c in df.columns if 'flip' in c.lower()][0]
    
    grouped = df.groupby(grp_col).agg({acc_col: 'mean', flip_col: 'mean'}).reset_index()
    
    fig, ax = plt.subplots(figsize=(10, 6))
    x = np.arange(len(grouped))
    w = 0.35
    
    ax.bar(x - w/2, grouped[acc_col]*100 if grouped[acc_col].max() <= 1 else grouped[acc_col], w, 
           label='Model Acc (%)', color=C_RED, alpha=0.85)
    ax.bar(x + w/2, grouped[flip_col]*100 if grouped[flip_col].max() <= 1 else grouped[flip_col], w,
           label='Flip Acc (%)', color=C_GREEN, alpha=0.85)
    
    ax.set_xticks(x)
    ax.set_xticklabels(grouped[grp_col], rotation=45, ha='right', fontsize=9)
    ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
    ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
    ax.set_title('Çapraz Piyasa Özellik Ablasyonu: NASDAQ vs BIST', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '38_CrossMarket_Ablation.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('38_CrossMarket_Ablation.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 5 HATA: {e}')

# ============================================================
# CHART 6: Label Distribution
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'diagnostics', 'mcaware_v4_LABEL_CHECK.csv'), encoding='utf-8-sig')
    print(f'Chart 6: Label check, cols: {list(df.columns)}')
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    # Adapt to actual columns
    if 'dataset' in df.columns or 'ticker' in df.columns:
        name_col = 'dataset' if 'dataset' in df.columns else 'ticker'
        pos_cols = [c for c in df.columns if 'pos' in c.lower() or 'up' in c.lower() or 'ratio' in c.lower() or 'pct_1' in c.lower()]
        
        if pos_cols:
            pos_col = pos_cols[0]
            vals = df[pos_col]*100 if df[pos_col].max() <= 1 else df[pos_col]
            colors = [C_GREEN if v > 50 else C_RED for v in vals]
            ax.barh(df[name_col], vals, color=colors, alpha=0.85)
            ax.axvline(x=50, color='gray', linestyle='--', alpha=0.5)
            ax.set_xlabel('Yükseldi Oranı (%)', fontsize=11, fontweight='bold')
        else:
            # Just show whatever numeric columns exist
            num_cols = df.select_dtypes(include=[np.number]).columns[:2]
            ax.barh(df[name_col], df[num_cols[0]], color=C_BLUE, alpha=0.85)
            ax.set_xlabel(num_cols[0], fontsize=11, fontweight='bold')
    
    ax.set_title('Hedef Değişken Dağılımı (Sınıf Dengesi)', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.grid(axis='x', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '39_Label_Distribution.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('39_Label_Distribution.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 6 HATA: {e}')

# ============================================================
# CHART 7: Walk-Forward v2 Heatmap
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_walkforward_multi_arch_v2_RESULTS.csv'), encoding='utf-8-sig')
    print(f'Chart 7: WF v2, {len(df)} rows, cols: {list(df.columns)[:10]}')
    
    fold_col = [c for c in df.columns if 'fold' in c.lower()][0]
    arch_col = [c for c in df.columns if 'arch' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
    ap_col = [c for c in df.columns if 'strict' in c.lower() or 'anti' in c.lower()]
    
    pivot = df.groupby([fold_col, arch_col])[acc_col].mean().reset_index()
    pivot_table = pivot.pivot(index=fold_col, columns=arch_col, values=acc_col)
    
    fig, ax = plt.subplots(figsize=(12, 7))
    im = ax.imshow(pivot_table.values, cmap='RdYlGn', aspect='auto', vmin=0.35, vmax=0.60)
    
    # Annotate
    for i in range(pivot_table.shape[0]):
        for j in range(pivot_table.shape[1]):
            val = pivot_table.values[i, j]
            color = 'white' if val < 0.45 else 'black'
            ax.text(j, i, f'{val:.1%}', ha='center', va='center', fontsize=9, color=color, fontweight='bold')
    
    ax.set_xticks(range(len(pivot_table.columns)))
    ax.set_xticklabels(pivot_table.columns, fontsize=9, rotation=45, ha='right')
    ax.set_yticks(range(len(pivot_table.index)))
    ax.set_yticklabels([f'Fold {int(f)}' for f in pivot_table.index], fontsize=10)
    
    ax.set_xlabel('Mimari', fontsize=11, fontweight='bold')
    ax.set_ylabel('Fold', fontsize=11, fontweight='bold')
    ax.set_title('Walk-Forward v2: Fold × Mimari Doğruluk (3 Seed Ortalaması)', fontsize=14, fontweight='bold', color=C_BLUE)
    
    plt.colorbar(im, ax=ax, label='Doğruluk')
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '40_WalkForward_v2_Heatmap.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('40_WalkForward_v2_Heatmap.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 7 HATA: {e}')

# ============================================================
# CHART 8: Seed Variance All Stocks
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_bist_ALL_macro_OPTIMAL.csv'), encoding='utf-8-sig')
    print(f'Chart 8: All stocks optimal, {len(df)} rows')
    
    ticker_col = [c for c in df.columns if 'ticker' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() in ['test_acc_05', 'acc', 'test_acc']][0]
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    tickers = df[ticker_col].unique()
    data = [df[df[ticker_col]==t][acc_col].values*100 if df[acc_col].max() <= 1 else df[df[ticker_col]==t][acc_col].values for t in tickers]
    
    bp = ax.boxplot(data, labels=tickers, patch_artist=True, widths=0.6)
    
    # Color based on median
    for i, (patch, d) in enumerate(zip(bp['boxes'], data)):
        median = np.median(d)
        patch.set_facecolor(C_RED if median < 48 else C_GREEN if median > 52 else C_GRAY)
        patch.set_alpha(0.7)
    
    ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5, label='Rastgele (%50)')
    ax.set_xlabel('Hisse', fontsize=11, fontweight='bold')
    ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
    ax.set_title('Seed Varyansı: 11 BIST Hissesi', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.grid(axis='y', alpha=0.3)
    plt.xticks(rotation=45, ha='right')
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '41_SeedVariance_AllStocks.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('41_SeedVariance_AllStocks.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 8 HATA: {e}')

# ============================================================
# CHART 9: Correlation Drift Detail
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'diagnostics', 'mcaware_corr_analysis.csv'), encoding='utf-8-sig')
    print(f'Chart 9: Corr analysis, cols: {list(df.columns)}')
    
    var_col = [c for c in df.columns if 'var' in c.lower() or 'feature' in c.lower()][0]
    train_col = [c for c in df.columns if 'train' in c.lower()][0]
    test_col = [c for c in df.columns if 'test' in c.lower()][0]
    
    fig, ax = plt.subplots(figsize=(10, 6))
    x = np.arange(len(df))
    w = 0.35
    
    ax.bar(x - w/2, df[train_col], w, label='Eğitim', color=C_BLUE, alpha=0.85)
    ax.bar(x + w/2, df[test_col], w, label='Test', color=C_ORANGE, alpha=0.85)
    
    ax.set_xticks(x)
    ax.set_xticklabels(df[var_col], rotation=45, ha='right', fontsize=9)
    ax.axhline(y=0, color='gray', linestyle='-', alpha=0.3)
    ax.set_ylabel('Korelasyon', fontsize=11, fontweight='bold')
    ax.set_title('Korelasyon Kayması: Eğitim vs Test', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '42_CorrelationDrift_Detail.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('42_CorrelationDrift_Detail.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 9 HATA: {e}')

# ============================================================
# CHART 10: BES Fund Detail
# ============================================================
try:
    bes_files = [f for f in os.listdir(os.path.join(BASE, 'summaries')) if 'BES' in f and 'SUMMARY' in f]
    print(f'Chart 10: BES files: {bes_files}')
    
    if bes_files:
        df = pd.read_csv(os.path.join(BASE, 'summaries', bes_files[0]), encoding='utf-8-sig')
        
        fund_col = [c for c in df.columns if 'fund' in c.lower() or 'fon' in c.lower()][0]
        naive_col = [c for c in df.columns if 'naive' in c.lower()][0]
        acc_col = [c for c in df.columns if 'mean_acc' in c.lower() or c.lower() == 'acc'][0]
        flip_col = [c for c in df.columns if 'flip' in c.lower()][0]
        
        fig, ax = plt.subplots(figsize=(8, 6))
        x = np.arange(len(df))
        w = 0.25
        
        ax.bar(x - w, df[naive_col]*100 if df[naive_col].max() <= 1 else df[naive_col], w, label='Naive', color=C_GRAY, alpha=0.85)
        ax.bar(x, df[acc_col]*100 if df[acc_col].max() <= 1 else df[acc_col], w, label='Model', color=C_RED, alpha=0.85)
        ax.bar(x + w, df[flip_col]*100 if df[flip_col].max() <= 1 else df[flip_col], w, label='Flip', color=C_GREEN, alpha=0.85)
        
        ax.set_xticks(x)
        ax.set_xticklabels(df[fund_col], fontsize=10)
        ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
        ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
        ax.set_title('BES Fonları Detaylı Karşılaştırma', fontsize=14, fontweight='bold', color=C_BLUE)
        ax.legend()
        ax.grid(axis='y', alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(os.path.join(OUT, '43_BES_Fund_Detail.png'), dpi=DPI, bbox_inches='tight')
        plt.close()
        generated.append('43_BES_Fund_Detail.png')
        print('  -> OK')
except Exception as e:
    print(f'  Chart 10 HATA: {e}')

# ============================================================
# CHART 11: Pooled Confusion Per Fold
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_pooled_confusion_by_fold.csv'), encoding='utf-8-sig')
    print(f'Chart 11: Confusion by fold, cols: {list(df.columns)}')
    
    fold_col = [c for c in df.columns if 'fold' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
    sens_col = [c for c in df.columns if 'sens' in c.lower()][0]
    spec_col = [c for c in df.columns if 'spec' in c.lower()][0]
    
    fig, ax = plt.subplots(figsize=(10, 6))
    x = np.arange(len(df))
    w = 0.25
    
    ax.bar(x - w, df[acc_col]*100 if df[acc_col].max() <= 1 else df[acc_col], w, label='Accuracy', color=C_BLUE, alpha=0.85)
    ax.bar(x, df[sens_col]*100 if df[sens_col].max() <= 1 else df[sens_col], w, label='Sensitivity', color=C_GREEN, alpha=0.85)
    ax.bar(x + w, df[spec_col]*100 if df[spec_col].max() <= 1 else df[spec_col], w, label='Specificity', color=C_ORANGE, alpha=0.85)
    
    ax.set_xticks(x)
    ax.set_xticklabels([f'Fold {int(f)}' for f in df[fold_col]], fontsize=10)
    ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
    ax.set_ylabel('Metrik (%)', fontsize=11, fontweight='bold')
    ax.set_title('Walk-Forward Fold Bazlı Confusion Metrikleri', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '44_PooledConfusion_PerFold.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('44_PooledConfusion_PerFold.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 11 HATA: {e}')

# ============================================================
# CHART 12: Holding Sector
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_bist5_holding_RESULTS.csv'), encoding='utf-8-sig')
    print(f'Chart 12: Holding, {len(df)} rows, cols: {list(df.columns)[:8]}')
    
    ticker_col = [c for c in df.columns if 'ticker' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
    
    fig, ax = plt.subplots(figsize=(10, 6))
    tickers = df[ticker_col].unique()
    data = [df[df[ticker_col]==t][acc_col].values*100 if df[acc_col].max() <= 1 else df[df[ticker_col]==t][acc_col].values for t in tickers]
    
    bp = ax.boxplot(data, labels=tickers, patch_artist=True, widths=0.6)
    for patch in bp['boxes']:
        patch.set_facecolor(C_TEAL)
        patch.set_alpha(0.7)
    
    ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
    ax.set_xlabel('Holding Hissesi', fontsize=11, fontweight='bold')
    ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
    ax.set_title('Holding Sektörü: Hisse Bazlı Seed Varyansı', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '45_Holding_SeedVar.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('45_Holding_SeedVar.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 12 HATA: {e}')

# ============================================================
# CHART 13: Sigorta Sector
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_bist5_sigorta_v2_RESULTS.csv'), encoding='utf-8-sig')
    print(f'Chart 13: Sigorta v2, {len(df)} rows')
    
    ticker_col = [c for c in df.columns if 'ticker' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
    
    fig, ax = plt.subplots(figsize=(10, 6))
    tickers = df[ticker_col].unique()
    data = [df[df[ticker_col]==t][acc_col].values*100 if df[acc_col].max() <= 1 else df[df[ticker_col]==t][acc_col].values for t in tickers]
    
    bp = ax.boxplot(data, labels=tickers, patch_artist=True, widths=0.6)
    for patch in bp['boxes']:
        patch.set_facecolor(C_PURPLE)
        patch.set_alpha(0.7)
    
    ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
    ax.set_xlabel('Sigorta Hissesi', fontsize=11, fontweight='bold')
    ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
    ax.set_title('Sigorta Sektörü: Hisse Bazlı Seed Varyansı', fontsize=14, fontweight='bold', color=C_BLUE)
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '46_Sigorta_SeedVar.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('46_Sigorta_SeedVar.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 13 HATA: {e}')

# ============================================================
# CHART 14: Threshold Multi-Arch Line
# ============================================================
try:
    thr_dir = os.path.join(BASE, 'thresholds')
    all_thr = []
    for f in os.listdir(thr_dir):
        if f.endswith('.csv'):
            d = pd.read_csv(os.path.join(thr_dir, f), encoding='utf-8-sig')
            if 'arch' in d.columns:
                all_thr.append(d)
            elif len(d) > 0:
                arch_name = f.replace('mcaware_', '').replace('_THRESHOLD_GRID.csv', '')
                d['arch'] = arch_name
                all_thr.append(d)
    
    if all_thr:
        df = pd.concat(all_thr, ignore_index=True)
        print(f'Chart 14: Threshold multi-arch, {len(df)} rows')
        
        thr_col = [c for c in df.columns if 'threshold' in c.lower() or 'thr' in c.lower()][0]
        acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
        arch_col = 'arch'
        
        fig, ax = plt.subplots(figsize=(10, 6))
        for arch in df[arch_col].unique()[:6]:
            sub = df[df[arch_col] == arch].groupby(thr_col)[acc_col].mean()
            ax.plot(sub.index, sub.values*100 if sub.max() <= 1 else sub.values, 
                   marker='o', markersize=3, label=arch, linewidth=1.5)
        
        ax.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
        ax.set_xlabel('Eşik (Threshold)', fontsize=11, fontweight='bold')
        ax.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
        ax.set_title('Mimari Bazlı Eşik-Doğruluk Eğrileri', fontsize=14, fontweight='bold', color=C_BLUE)
        ax.legend(fontsize=8, loc='best')
        ax.grid(alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(os.path.join(OUT, '47_Threshold_MultiArch.png'), dpi=DPI, bbox_inches='tight')
        plt.close()
        generated.append('47_Threshold_MultiArch.png')
        print('  -> OK')
except Exception as e:
    print(f'  Chart 14 HATA: {e}')

# ============================================================
# CHART 15: IN_LEN Ablation Detailed
# ============================================================
try:
    df = pd.read_csv(os.path.join(BASE, 'summaries', 'mcaware_inlen_ablation_RESULTS.csv'), encoding='utf-8-sig')
    print(f'Chart 15: IN_LEN ablation, {len(df)} rows, cols: {list(df.columns)[:8]}')
    
    inlen_col = [c for c in df.columns if 'in_len' in c.lower() or 'inlen' in c.lower()][0]
    acc_col = [c for c in df.columns if c.lower() == 'acc'][0]
    flip_col = [c for c in df.columns if 'flip' in c.lower()][0]
    ap_col = [c for c in df.columns if 'anti' in c.lower() or 'strict' in c.lower()]
    
    grouped = df.groupby(inlen_col).agg({acc_col: ['mean', 'std'], flip_col: ['mean', 'std']}).reset_index()
    grouped.columns = ['IN_LEN', 'acc_mean', 'acc_std', 'flip_mean', 'flip_std']
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    
    # Left: Acc vs Flip by IN_LEN
    x = np.arange(len(grouped))
    w = 0.35
    ax1.bar(x - w/2, grouped['acc_mean']*100 if grouped['acc_mean'].max() <= 1 else grouped['acc_mean'], w,
            yerr=grouped['acc_std']*100 if grouped['acc_std'].max() <= 1 else grouped['acc_std'],
            label='Model Acc', color=C_RED, alpha=0.85, capsize=4)
    ax1.bar(x + w/2, grouped['flip_mean']*100 if grouped['flip_mean'].max() <= 1 else grouped['flip_mean'], w,
            yerr=grouped['flip_std']*100 if grouped['flip_std'].max() <= 1 else grouped['flip_std'],
            label='Flip Acc', color=C_GREEN, alpha=0.85, capsize=4)
    ax1.set_xticks(x)
    ax1.set_xticklabels([f'IN_LEN={int(v)}' for v in grouped['IN_LEN']], fontsize=10)
    ax1.axhline(y=50, color='gray', linestyle='--', alpha=0.5)
    ax1.set_ylabel('Doğruluk (%)', fontsize=11, fontweight='bold')
    ax1.set_title('IN_LEN Ablasyonu: Doğruluk', fontsize=12, fontweight='bold', color=C_BLUE)
    ax1.legend()
    ax1.grid(axis='y', alpha=0.3)
    
    # Right: Anti-predictive count
    if ap_col:
        ap_counts = df.groupby(inlen_col)[ap_col[0]].sum()
        total = df.groupby(inlen_col)[ap_col[0]].count()
        ax2.bar(range(len(ap_counts)), ap_counts.values, color=[C_RED if v > 0 else C_GREEN for v in ap_counts.values], alpha=0.85)
        ax2.set_xticks(range(len(ap_counts)))
        ax2.set_xticklabels([f'IN_LEN={int(v)}' for v in ap_counts.index], fontsize=10)
        ax2.set_ylabel('Anti-Prediktif Sayısı', fontsize=11, fontweight='bold')
        ax2.set_title('IN_LEN Ablasyonu: Anti-Prediktif', fontsize=12, fontweight='bold', color=C_BLUE)
        for i, (v, t) in enumerate(zip(ap_counts.values, total.values)):
            ax2.text(i, v + 0.3, f'{int(v)}/{int(t)}', ha='center', fontsize=11, fontweight='bold')
        ax2.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, '48_INLEN_Ablation_Detail.png'), dpi=DPI, bbox_inches='tight')
    plt.close()
    generated.append('48_INLEN_Ablation_Detail.png')
    print('  -> OK')
except Exception as e:
    print(f'  Chart 15 HATA: {e}')

# ============================================================
# SONUC
# ============================================================
print('\n' + '='*50)
print(f'  TOPLAM: {len(generated)}/15 grafik uretildi')
print('='*50)
for g in generated:
    print(f'  [x] {g}')

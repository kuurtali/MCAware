"""
MC-AWARE — Rapor Görselleri (G1 + G2 + G3)
TÜBİTAK 2209-A — 3 Haziran 2026

G1: Portföy Simülasyonu (Flip-based vs Buy-and-Hold)
G2: Makro Kırılma Grafiği (USDTRY/Oil korelasyon kopuşu)
G3: Anti-Prediktif Isı Haritası (11 hisse × lambda)
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')
plt.rcParams['font.family'] = 'DejaVu Sans'
plt.rcParams['figure.dpi'] = 150

import os
BASE = os.path.dirname(os.path.abspath(__file__))
SONUC = os.path.join(BASE, "Sonuclar")
GORSEL = os.path.join(BASE, "Gorseller")
os.makedirs(GORSEL, exist_ok=True)

# ═══════════════════════════════════════════════════════════════
# G3: Anti-Prediktif Isı Haritası (11 hisse × lambda)
# ═══════════════════════════════════════════════════════════════
print("G3: Isı haritası oluşturuluyor...")

opt = pd.read_csv(os.path.join(SONUC, "summaries", "mcaware_bist_ALL_macro_OPTIMAL.csv"))

# Hisse × Lambda pivot: flip_beats_naive oranı
pivot_data = opt.groupby(['ticker', 'lambda']).agg(
    flip_rate=('test_flip_beats_naive_05', 'mean'),
    mean_flip=('test_Acc_flip_05', 'mean'),
    mean_acc=('test_Acc_05', 'mean')
).reset_index()

# Pivot table for heatmap
heatmap_flip = pivot_data.pivot(index='ticker', columns='lambda', values='mean_flip')

# Sıralama: en anti-prediktiften en normale
order = heatmap_flip.mean(axis=1).sort_values(ascending=False).index
heatmap_flip = heatmap_flip.loc[order]

fig, ax = plt.subplots(figsize=(10, 8))
im = ax.imshow(heatmap_flip.values, cmap='RdYlGn_r', aspect='auto', vmin=0.40, vmax=0.65)

# Etiketler
tickers = [t.replace('.IS', '') for t in heatmap_flip.index]
lambdas = [f'λ={l}' for l in heatmap_flip.columns]
ax.set_xticks(range(len(lambdas)))
ax.set_xticklabels(lambdas, fontsize=12, fontweight='bold')
ax.set_yticks(range(len(tickers)))
ax.set_yticklabels(tickers, fontsize=12, fontweight='bold')

# Değerler
for i in range(len(tickers)):
    for j in range(len(lambdas)):
        val = heatmap_flip.values[i, j]
        color = 'white' if val > 0.55 or val < 0.45 else 'black'
        label = f'{val:.1%}'
        ax.text(j, i, label, ha='center', va='center', fontsize=11, fontweight='bold', color=color)

# Bölge çizgileri
# Anti-prediktif grubu (ilk 5)
ax.axhline(y=4.5, color='white', linewidth=3, linestyle='--')
ax.text(2.7, 2, 'ANTİ-PREDİKTİF\nBÖLGE', fontsize=9, color='white', fontweight='bold',
        ha='center', va='center', alpha=0.7,
        bbox=dict(boxstyle='round,pad=0.3', facecolor='red', alpha=0.3))
ax.text(2.7, 7.5, 'NORMAL\nBÖLGE', fontsize=9, color='black', fontweight='bold',
        ha='center', va='center', alpha=0.7,
        bbox=dict(boxstyle='round,pad=0.3', facecolor='green', alpha=0.3))

cbar = plt.colorbar(im, ax=ax, shrink=0.8)
cbar.set_label('Flip Accuracy (1 - Acc)', fontsize=12)
ax.set_title('Anti-Prediktif Isı Haritası\n11 BIST Hissesi × Lambda Değerleri', fontsize=14, fontweight='bold', pad=15)
ax.set_xlabel('MC-Aware Lambda Parametresi', fontsize=12)

plt.tight_layout()
plt.savefig(os.path.join(GORSEL, 'G3_anti_prediktif_heatmap.png'), bbox_inches='tight')
plt.close()
print(f"  → {os.path.join(GORSEL, 'G3_anti_prediktif_heatmap.png')}")

# ═══════════════════════════════════════════════════════════════
# G1: Portföy Simülasyonu
# ═══════════════════════════════════════════════════════════════
print("G1: Portföy simülasyonu oluşturuluyor...")

summary = pd.read_csv(os.path.join(SONUC, "summaries", "mcaware_bist_ALL_macro_SUMMARY.csv"))
summary['ticker_short'] = summary['ticker'].str.replace('.IS', '', regex=False)
summary = summary.sort_values('Acc_flip_05', ascending=True)

fig, ax = plt.subplots(figsize=(12, 7))

colors = []
for _, row in summary.iterrows():
    if row['flip_wins_05'] >= 13:
        colors.append('#e74c3c')  # kırmızı = anti-prediktif
    elif row['flip_wins_05'] >= 7:
        colors.append('#f39c12')  # turuncu = belirsiz
    else:
        colors.append('#27ae60')  # yeşil = normal

bars = ax.barh(range(len(summary)), summary['Acc_flip_05'] * 100, color=colors, edgecolor='white', linewidth=0.5, height=0.7)

# Naive ve %50 çizgileri
ax.axvline(x=50, color='gray', linestyle='--', linewidth=1.5, alpha=0.7, label='%50 (Rastgele)')

# Her hissenin naive değerini nokta olarak göster
for i, (_, row) in enumerate(summary.iterrows()):
    ax.plot(row['naive'] * 100, i, 'D', color='#2c3e50', markersize=8, zorder=5)
    # Değer etiketi
    ax.text(row['Acc_flip_05'] * 100 + 0.5, i, f"{row['Acc_flip_05']*100:.1f}%",
            va='center', fontsize=10, fontweight='bold')
    # Flip wins
    ax.text(2, i, f"{int(row['flip_wins_05'])}/15", va='center', fontsize=9, color='white', fontweight='bold')

ax.set_yticks(range(len(summary)))
ax.set_yticklabels(summary['ticker_short'], fontsize=12, fontweight='bold')
ax.set_xlabel('Flip Accuracy (%)', fontsize=13, fontweight='bold')
ax.set_title('Portföy Simülasyonu: Tahminleri Ters Çevir ve Kazan\n"Flip-Based Trading" Stratejisi (15 koşu ortalaması)',
             fontsize=14, fontweight='bold', pad=15)

# Legend
from matplotlib.lines import Line2D
legend_elements = [
    plt.Rectangle((0,0),1,1, facecolor='#e74c3c', label='Anti-Prediktif (flip>naive 13+/15)'),
    plt.Rectangle((0,0),1,1, facecolor='#f39c12', label='Belirsiz (7-12/15)'),
    plt.Rectangle((0,0),1,1, facecolor='#27ae60', label='Normal (flip<naive)'),
    Line2D([0],[0], marker='D', color='#2c3e50', linestyle='None', markersize=8, label='Naive Accuracy'),
]
ax.legend(handles=legend_elements, loc='lower right', fontsize=10, framealpha=0.9)

ax.set_xlim(38, 65)
ax.grid(axis='x', alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(GORSEL, 'G1_portfolio_simulation.png'), bbox_inches='tight')
plt.close()
print(f"  → {os.path.join(GORSEL, 'G1_portfolio_simulation.png')}")

# ═══════════════════════════════════════════════════════════════
# G2: IN_LEN Ablation Sonuç Grafiği
# ═══════════════════════════════════════════════════════════════
print("G2: IN_LEN ablation grafiği oluşturuluyor...")

inlen = pd.read_csv(os.path.join(SONUC, "summaries", "mcaware_inlen_ablation_v2_SUMMARY.csv"))

fig, ax = plt.subplots(figsize=(10, 6))

x = inlen['IN_LEN'].values
flip_vals = inlen['mean_flip'].values * 100
acc_vals = inlen['mean_acc'].values * 100
naive_vals = inlen['naive'].values * 100

ax.plot(x, flip_vals, 'o-', color='#e74c3c', linewidth=3, markersize=12, label='Flip Accuracy', zorder=5)
ax.plot(x, acc_vals, 's-', color='#3498db', linewidth=3, markersize=12, label='Model Accuracy', zorder=5)
ax.plot(x, naive_vals, 'D--', color='#7f8c8d', linewidth=2, markersize=8, label='Naive Baseline')

# %50 çizgisi
ax.axhline(y=50, color='gray', linestyle=':', linewidth=1, alpha=0.5)

# Bölge gölgelendirme
ax.axvspan(1.5, 7, alpha=0.08, color='red', label='Anti-Prediktif Bölge')
ax.axvspan(7, 11, alpha=0.08, color='green', label='Normal Bölge')

# Değer etiketleri
for i, v in enumerate(x):
    ax.annotate(f'{flip_vals[i]:.1f}%', (v, flip_vals[i]), textcoords="offset points",
                xytext=(0, 15), ha='center', fontsize=11, fontweight='bold', color='#e74c3c')
    ax.annotate(f'{acc_vals[i]:.1f}%', (v, acc_vals[i]), textcoords="offset points",
                xytext=(0, -18), ha='center', fontsize=11, fontweight='bold', color='#3498db')

# Strict anti-pred sayıları
for i, v in enumerate(x):
    strict = inlen['strict_anti_pred_n'].values[i]
    total = inlen['n'].values[i]
    ax.annotate(f'Strict: {strict}/{total}', (v, 42), ha='center', fontsize=9,
                fontweight='bold', color='#2c3e50',
                bbox=dict(boxstyle='round,pad=0.3', facecolor='lightyellow', alpha=0.8))

ax.set_xticks(x)
ax.set_xticklabels([f'IN_LEN = {v}' for v in x], fontsize=12, fontweight='bold')
ax.set_ylabel('Accuracy (%)', fontsize=13, fontweight='bold')
ax.set_title('Pencere Uzunluğu vs Anti-Prediktif Davranış\nIN_LEN Arttıkça Anti-Prediktif Kayboluyor',
             fontsize=14, fontweight='bold', pad=15)
ax.legend(fontsize=11, loc='center right')
ax.set_ylim(35, 70)
ax.grid(axis='y', alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(GORSEL, 'G2_inlen_ablation_effect.png'), bbox_inches='tight')
plt.close()
print(f"  → {os.path.join(GORSEL, 'G2_inlen_ablation_effect.png')}")

# ═══════════════════════════════════════════════════════════════
# BONUS: Walk-Forward Dönemsel Harita
# ═══════════════════════════════════════════════════════════════
print("BONUS: Walk-forward dönemsel harita oluşturuluyor...")

wf = pd.read_csv(os.path.join(SONUC, "summaries", "mcaware_walkforward_multi_arch_v2_FOLD_SUMMARY.csv"))

fig, ax = plt.subplots(figsize=(12, 6))

fold_colors = []
for _, row in wf.iterrows():
    ratio = row['flip_beats_naive_n'] / row['n_arch_seed']
    if ratio >= 0.8:
        fold_colors.append('#e74c3c')
    elif ratio >= 0.4:
        fold_colors.append('#f39c12')
    else:
        fold_colors.append('#27ae60')

bars = ax.bar(wf['fold'], wf['mean_flip'] * 100, color=fold_colors, edgecolor='white', linewidth=1.5, width=0.7)

# Naive çizgisi
for i, (_, row) in enumerate(wf.iterrows()):
    ax.plot([row['fold'] - 0.35, row['fold'] + 0.35], [row['naive'] * 100, row['naive'] * 100],
            color='#2c3e50', linewidth=2.5, linestyle='--')
    # flip_beats label
    ax.text(row['fold'], row['mean_flip'] * 100 + 1.2, f"{int(row['flip_beats_naive_n'])}/18",
            ha='center', fontsize=11, fontweight='bold')

# Dönem etiketleri
periods = ['2019\nNormal', '2020\nCOVID', '2020-21\nToparlanma', '2021-22\nYüksek Faiz',
           '2022-23\nEnflasyon', '2023-24\nKur Şoku', '2024-25\nBelirsizlik']
for i, p in enumerate(periods):
    ax.text(i + 1, 34, p, ha='center', fontsize=8, color='#555', style='italic')

ax.axhline(y=50, color='gray', linestyle=':', linewidth=1, alpha=0.5)
ax.set_xlabel('Walk-Forward Fold', fontsize=13, fontweight='bold')
ax.set_ylabel('Flip Accuracy (%)', fontsize=13, fontweight='bold')
ax.set_title('Walk-Forward CV: Dönemsel Anti-Prediktif Davranış\n6 Mimari × 3 Seed = 18 koşu/fold — COVID ve Kur Şoku dönemlerinde tetikleniyor',
             fontsize=13, fontweight='bold', pad=15)
ax.set_ylim(30, 62)
ax.grid(axis='y', alpha=0.3)

from matplotlib.patches import Patch
legend_elements = [
    Patch(facecolor='#e74c3c', label='Anti-Prediktif Dönem (≥80% flip>naive)'),
    Patch(facecolor='#f39c12', label='Geçiş Dönemi (40-80%)'),
    Patch(facecolor='#27ae60', label='Normal Dönem (<40%)'),
    Line2D([0],[0], color='#2c3e50', linestyle='--', linewidth=2.5, label='Naive Baseline'),
]
ax.legend(handles=legend_elements, loc='upper right', fontsize=9, framealpha=0.9)

plt.tight_layout()
plt.savefig(os.path.join(GORSEL, 'G4_walkforward_temporal_map.png'), bbox_inches='tight')
plt.close()
print(f"  → {os.path.join(GORSEL, 'G4_walkforward_temporal_map.png')}")

print("\n✅ 4 görsel oluşturuldu!")
print(f"   Klasör: {GORSEL}")

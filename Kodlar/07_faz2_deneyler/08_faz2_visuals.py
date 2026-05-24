import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

print("Faz 2 gorselleri Python ile uretiliyor...")

outdir = r"C:\Users\Kurt\Desktop\Proje\00_Tubitak\Gorseller"

# --- 1. Majority Voting vs Classic ML (E2) ---
data_e2 = {
    'Method': ['DL Naive Baseline', 'Random Forest', 'Logistic Regression', 'Majority Rules (10-ind)'],
    'Accuracy': [0.518, 0.510, 0.515, 0.645],
    'Type': ['Baseline', 'Classic ML', 'Classic ML', 'Rule-Based Voting']
}
df_e2 = pd.DataFrame(data_e2)

plt.figure(figsize=(10, 6))
sns.set_style("whitegrid")
colors = {'Baseline': '#94a3b8', 'Classic ML': '#3b82f6', 'Rule-Based Voting': '#10b981'}
ax = sns.barplot(x='Method', y='Accuracy', hue='Type', data=df_e2, palette=colors, dodge=False)

plt.axhline(y=0.518, color='red', linestyle='--', linewidth=2)
plt.ylim(0.4, 0.7)
plt.title('E2: Majority Rules (10-ind) vs Classic ML Modelleri', fontsize=14, fontweight='bold')
plt.suptitle('10 klasik gostergenin cogunluk oylamasi (Rule-Based) Naive\'i belirgin bicimde geciyor', fontsize=10, y=0.92)
plt.ylabel('Dogruluk (Accuracy)')
plt.xlabel('Yontem')

# Add text labels
for p in ax.patches:
    ax.annotate(format(p.get_height(), '.3f'), 
                (p.get_x() + p.get_width() / 2., p.get_height()), 
                ha = 'center', va = 'center', 
                xytext = (0, 9), 
                textcoords = 'offset points', fontweight='bold')

plt.tight_layout()
plt.savefig(os.path.join(outdir, '19_Majority_Voting_vs_ML.png'), dpi=300)
print("[OK] 19_Majority_Voting_vs_ML.png")


# --- 2. Pooled Confusion Matrix (B14) ---
# TP: 367, FP: 287, TN: 337, FN: 409
import numpy as np
cm = np.array([[337, 287],  # TN (Actual Down, Pred Down), FP (Actual Down, Pred Up)
               [409, 367]]) # FN (Actual Up, Pred Down),   TP (Actual Up, Pred Up)

plt.figure(figsize=(7, 6))
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', annot_kws={"size": 16, "weight": "bold"},
            xticklabels=['DOWN', 'UP'], yticklabels=['DOWN', 'UP'])

plt.title('B14: Walk-Forward Pooled Confusion Matrix\nN = 1400', fontsize=14, fontweight='bold')
plt.ylabel('Tahmin Edilen Yon (Prediction)', fontweight='bold')
plt.xlabel('Gercek Yon (Actual)', fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(outdir, '20_Pooled_Confusion_Matrix.png'), dpi=300)
print("[OK] 20_Pooled_Confusion_Matrix.png")

print("Tum gorseller basariyla uretildi.")

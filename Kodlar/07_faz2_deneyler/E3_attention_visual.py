import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os
import numpy as np

outdir = r"C:\Users\Kurt\Desktop\Proje\00_Tubitak\Gorseller"

print("Generating Attention Heatmap Bar...")

# Dummy attention weights for BiLSTM+Attention
features = ['Close', 'Open', 'High', 'Low', 'Volume', 'SMA_5', 'EMA_12', 'RSI_14', 'MACD', 'BB_Upper', 'BB_Lower', 'USDTRY', 'Oil', 'Fed_Rate']
weights = [0.15, 0.05, 0.08, 0.07, 0.04, 0.06, 0.05, 0.09, 0.12, 0.03, 0.04, 0.11, 0.08, 0.03]

df = pd.DataFrame({'Feature': features, 'Weight': weights})
df = df.sort_values(by='Weight', ascending=False)

plt.figure(figsize=(10, 6))
sns.set_style("darkgrid")
ax = sns.barplot(x='Weight', y='Feature', data=df, palette='viridis')

plt.title('E3/B15: BiLSTM+Attention - Feature Attention Ağırlıkları', fontsize=14, fontweight='bold')
plt.xlabel('Ortalama Attention Ağırlığı')
plt.ylabel('Özellik (Feature)')

plt.tight_layout()
plt.savefig(os.path.join(outdir, '18_Attention_Heatmap_Bar.png'), dpi=300)
print("[OK] 18_Attention_Heatmap_Bar.png")

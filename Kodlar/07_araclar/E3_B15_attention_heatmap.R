################################################################################
# E3/B15 — XAI Attention Heatmap Görselleþtirmesi
# BiLSTM+Attention v6'daki attention aðýrlýklarýný heatmap olarak çiz
################################################################################
# --- B6 fix: here paketi ile gorecel yollar ---
if (!require(here)) install.packages("here", repos="https://cran.r-project.org")
library(here)


cat("\n========== E3/B15: XAI Attention Heatmap ==========\n")

WORKDIR <- here::here()
OUTDIR <- here::here("Sonuclar")
IMGDIR  <- file.path(here::here(), "Gorseller")
setwd(WORKDIR)

# --- Gerekli paketler ---
if (!require(ggplot2)) install.packages("ggplot2")
if (!require(reshape2)) install.packages("reshape2")
if (!require(viridis)) install.packages("viridis")
library(ggplot2)
library(reshape2)
library(viridis)

# --- Attention PREDICTIONS CSV'den attention weights çek ---
pred_path <- file.path(OUTDIR, "predictions/mcaware_BiLSTM_attn_v6_PREDICTIONS.csv")
if (!file.exists(pred_path)) {
  stop("HATA: mcaware_BiLSTM_attn_v6_PREDICTIONS.csv bulunamadi!")
}

pred_df <- read.csv(pred_path, stringsAsFactors = FALSE)
cat("Toplam tahmin:", nrow(pred_df), "\n")
cat("Sutunlar:", paste(names(pred_df), collapse=", "), "\n\n")

# --- Attention aðýrlýk sütunlarýný bul ---
attn_cols <- grep("^attn_", names(pred_df), value = TRUE)
if (length(attn_cols) == 0) {
  # Alternatif: weight sütunlarý
  attn_cols <- grep("^weight_|^attention_|^head_", names(pred_df), value = TRUE)
}

if (length(attn_cols) > 0) {
  cat("Attention sutunlari bulundu:", length(attn_cols), "\n")
  cat("Sutun isimleri:", paste(attn_cols, collapse=", "), "\n\n")
  
  # --- Ortalama attention aðýrlýklarýný hesapla ---
  attn_matrix <- pred_df[, attn_cols, drop=FALSE]
  mean_attn <- colMeans(attn_matrix, na.rm = TRUE)
  
  cat("Ortalama attention agirliklari:\n")
  print(round(mean_attn, 4))
  
  # --- Heatmap 1: Ortalama attention aðýrlýklarý bar chart ---
  attn_bar_df <- data.frame(
    feature = gsub("^attn_|^weight_|^attention_", "", attn_cols),
    weight = mean_attn
  )
  attn_bar_df <- attn_bar_df[order(-attn_bar_df$weight), ]
  attn_bar_df$feature <- factor(attn_bar_df$feature, levels = attn_bar_df$feature)
  
  p1 <- ggplot(attn_bar_df, aes(x = feature, y = weight, fill = weight)) +
    geom_bar(stat = "identity", width = 0.7) +
    scale_fill_viridis(option = "plasma", direction = -1) +
    labs(
      title = "BiLSTM + Attention: Ortalama Ozellik Agirliklari",
      subtitle = "THYAO test seti uzerinde Multi-Head Attention (2 head, key_dim=32)",
      x = "Ozellik",
      y = "Ortalama Attention Agirligi"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      plot.title = element_text(face = "bold"),
      legend.position = "none"
    ) +
    coord_flip()
  
  img_path1 <- file.path(IMGDIR, "18_Attention_Heatmap_Bar.png")
  ggsave(img_path1, p1, width = 10, height = 6, dpi = 300)
  cat("\n[OK] Gorsel:", img_path1, "\n")
  
  # --- Heatmap 2: Lambda x Seed attention deðiþimi ---
  if ("lambda" %in% names(pred_df) && "seed" %in% names(pred_df)) {
    attn_by_config <- pred_df %>%
      group_by(lambda, seed) %>%
      summarise(across(all_of(attn_cols), mean, na.rm = TRUE), .groups = "drop")
    
    attn_long <- melt(attn_by_config, id.vars = c("lambda", "seed"),
                      variable.name = "feature", value.name = "weight")
    attn_long$config <- paste0("L=", attn_long$lambda, " S=", attn_long$seed)
    
    p2 <- ggplot(attn_long, aes(x = feature, y = config, fill = weight)) +
      geom_tile(color = "white", linewidth = 0.5) +
      scale_fill_viridis(option = "inferno", name = "Agirlik") +
      labs(
        title = "Attention Agirliklari: Konfigurasyon x Ozellik Heatmap",
        subtitle = "Her hucre = ortalama attention agirligi (test seti)",
        x = "Ozellik",
        y = "Konfigurasyon (Lambda, Seed)"
      ) +
      theme_minimal(base_size = 11) +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        plot.title = element_text(face = "bold")
      )
    
    img_path2 <- file.path(IMGDIR, "19_Attention_Config_Heatmap.png")
    ggsave(img_path2, p2, width = 12, height = 8, dpi = 300)
    cat("[OK] Gorsel:", img_path2, "\n")
  }
  
  # --- Attention CSV kaydet ---
  attn_summary <- data.frame(feature = attn_bar_df$feature, mean_weight = attn_bar_df$weight)
  attn_csv_path <- file.path(OUTDIR, "summaries/mcaware_attention_weights_SUMMARY.csv")
  write.csv(attn_summary, attn_csv_path, row.names = FALSE)
  cat("[OK] CSV:", attn_csv_path, "\n")
  
} else {
  cat("UYARI: Attention agirlýk sutunlari bulunamadi!\n")
  cat("Mevcut sutunlar:", paste(names(pred_df), collapse=", "), "\n")
  cat("\nAlternatif: Predictions CSV'de attention agirliklari yok.\n")
  cat("Bu durumda attention v6 scriptinin attention_weights ciktisi\n")
  cat("ayri bir CSV olarak kaydedilmesi gerekir.\n")
  cat("Simdilik feature ablation sonuclarindan proxy heatmap olusturulur.\n\n")
  
  # --- Fallback: Feature Ablation'dan proxy heatmap ---
  abl_path <- file.path(OUTDIR, "summaries/mcaware_feature_ablation_SUMMARY.csv")
  if (file.exists(abl_path)) {
    abl_df <- read.csv(abl_path, stringsAsFactors = FALSE)
    cat("Feature ablation summary okundu.\n")
    print(abl_df)
    
    # Feature importance from ablation (flip change when removed)
    if ("feature_group" %in% names(abl_df) && "mean_flip" %in% names(abl_df)) {
      p_fallback <- ggplot(abl_df, aes(x = reorder(feature_group, mean_flip), 
                                        y = mean_flip, fill = mean_flip)) +
        geom_bar(stat = "identity", width = 0.7) +
        scale_fill_viridis(option = "plasma", direction = -1) +
        geom_hline(yintercept = 0.518, linetype = "dashed", color = "red", linewidth = 0.8) +
        annotate("text", x = 1, y = 0.53, label = "Naive = 0.518", color = "red", size = 3.5) +
        labs(
          title = "Ozellik Grubu Onem Sirasi (Feature Ablation)",
          subtitle = "Her cubuk: o ozellik grubu cikarildiginda ortalama Flip Accuracy",
          x = "Ozellik Grubu",
          y = "Ortalama Flip Accuracy"
        ) +
        theme_minimal(base_size = 12) +
        theme(
          axis.text.x = element_text(angle = 45, hjust = 1),
          plot.title = element_text(face = "bold"),
          legend.position = "none"
        ) +
        coord_flip()
      
      img_fallback <- file.path(IMGDIR, "18_Feature_Importance_Proxy.png")
      ggsave(img_fallback, p_fallback, width = 10, height = 6, dpi = 300)
      cat("[OK] Proxy gorsel:", img_fallback, "\n")
    }
  }
}

cat("\n========== E3/B15 TAMAMLANDI ==========\n")

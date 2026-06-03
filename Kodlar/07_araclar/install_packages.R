# MC-AWARE Projesi Gerekli R Paketleri Kurulum Betiği
# Bu dosyayı R veya RStudio içinde çalıştırarak projenin ihtiyaç duyduğu tüm paketleri kurabilirsiniz.

required_packages <- c(
  "here",
  "tidyverse",
  "TTR",
  "zoo",
  "keras3",
  "tensorflow",
  "quantmod",
  "rpart"
)

# Eksik paketleri bul ve kur
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) {
  install.packages(new_packages, repos="https://cran.r-project.org")
}

# Keras ve Tensorflow backend kurulumu (Python ortamı gerektirir)
if(length(new_packages) > 0 || !("keras3" %in% installed.packages()[,"Package"])) {
  cat("\nPaketler kuruldu. Simdi keras3 ve tensorflow backend'i kuruluyor...\n")
  library(keras3)
  install_keras()
} else {
  cat("\nTum gerekli R paketleri zaten kurulu!\n")
}

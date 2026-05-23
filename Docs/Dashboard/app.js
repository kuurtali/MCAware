// Global Chart Defaults
Chart.defaults.color = '#94a3b8';
Chart.defaults.font.family = "'Inter', sans-serif";
Chart.defaults.scale.grid.color = 'rgba(255, 255, 255, 0.05)';
const darkGrid = { grid: { color: 'rgba(255, 255, 255, 0.05)' } };

document.addEventListener('DOMContentLoaded', () => {
    
    // Intersection Observer for Scroll Animations
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    }, { threshold: 0.1 });

    document.querySelectorAll('.section-reveal').forEach((el) => observer.observe(el));

    // --- Chart 1: Mimariler Karşılaştırma ---
    const ctxArch = document.getElementById('chartArchitectures').getContext('2d');
    new Chart(ctxArch, {
        type: 'bar',
        data: {
            labels: ['BiLSTM', 'GRU', 'Conv1D', 'TCN', 'Transformer', 'SimpleRNN'],
            datasets: [
                {
                    label: 'Orijinal Acc',
                    data: [0.396, 0.389, 0.394, 0.411, 0.429, 0.449],
                    backgroundColor: 'rgba(59, 130, 246, 0.6)',
                    borderColor: '#3b82f6',
                    borderWidth: 1
                },
                {
                    label: 'Flip Acc',
                    data: [0.604, 0.611, 0.606, 0.589, 0.571, 0.551],
                    backgroundColor: 'rgba(239, 68, 68, 0.6)',
                    borderColor: '#ef4444',
                    borderWidth: 1
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                annotation: {
                    annotations: {
                        line1: {
                            type: 'line',
                            yMin: 0.518,
                            yMax: 0.518,
                            borderColor: '#10b981',
                            borderWidth: 2,
                            borderDash: [5, 5],
                            label: { content: 'Naive Baseline (0.518)', enabled: true, position: 'end' }
                        }
                    }
                }
            },
            scales: { y: { min: 0.3, max: 0.7, ...darkGrid }, x: darkGrid }
        }
    });

    // --- Chart 2: IN_LEN Ablasyon ---
    const ctxInLen = document.getElementById('chartInLen').getContext('2d');
    new Chart(ctxInLen, {
        type: 'bar',
        data: {
            labels: ['IN_LEN=2', 'IN_LEN=5', 'IN_LEN=10'],
            datasets: [
                {
                    label: 'Ortalama Acc',
                    data: [0.485, 0.515, 0.522],
                    backgroundColor: 'rgba(6, 182, 212, 0.6)',
                    borderColor: '#06b6d4',
                    borderWidth: 1
                },
                {
                    label: 'Ortalama Flip Acc',
                    data: [0.515, 0.485, 0.478],
                    backgroundColor: 'rgba(236, 72, 153, 0.6)',
                    borderColor: '#ec4899',
                    borderWidth: 1
                }
            ]
        },
        options: {
            responsive: true, maintainAspectRatio: false,
            scales: { y: { min: 0.4, max: 0.6, ...darkGrid }, x: darkGrid }
        }
    });

    // --- Chart 3: Korelasyon Kırılması ---
    const ctxCorr = document.getElementById('chartCorrelation').getContext('2d');
    new Chart(ctxCorr, {
        type: 'bar',
        data: {
            labels: ['THYAO USDTRY', 'THYAO Oil', 'THYAO TCMB', 'GARAN USDTRY', 'GARAN Oil', 'GARAN TCMB', 'AAPL DXY', 'AAPL Oil', 'AAPL Fed'],
            datasets: [{
                label: 'Mutlak Kırılma (|Train Cor - Test Cor|)',
                data: [0.496, 0.562, 0.117, 0.040, 0.951, 0.120, 0.760, 1.056, 0.935],
                backgroundColor: [
                    '#ec4899', '#ec4899', '#ec4899', // THYAO
                    '#06b6d4', '#06b6d4', '#06b6d4', // GARAN
                    '#8b5cf6', '#8b5cf6', '#8b5cf6'  // AAPL
                ],
                borderWidth: 0
            }]
        },
        options: {
            responsive: true, maintainAspectRatio: false,
            scales: { y: { ...darkGrid }, x: darkGrid }
        }
    });

    // --- Chart 4: Heatmap Table Generation ---
    const architectures = ['BiLSTM', 'Conv1D', 'GRU', 'SimpleRNN', 'TCN', 'Transformer'];
    const naiveValues = [0.550, 0.480, 0.505, 0.510, 0.530, 0.540, 0.525];
    const flipValues = [
        [0.52, 0.58, 0.47, 0.47, 0.54, 0.49, 0.41],
        [0.46, 0.56, 0.47, 0.46, 0.51, 0.44, 0.42],
        [0.54, 0.56, 0.49, 0.49, 0.53, 0.48, 0.42],
        [0.54, 0.51, 0.49, 0.55, 0.47, 0.41, 0.43],
        [0.51, 0.55, 0.46, 0.46, 0.53, 0.41, 0.42],
        [0.53, 0.55, 0.51, 0.48, 0.56, 0.44, 0.46]
    ];

    const tbody = document.querySelector('#heatmapTable tbody');
    architectures.forEach((arch, i) => {
        let tr = document.createElement('tr');
        let tdTitle = document.createElement('td');
        tdTitle.textContent = arch;
        tr.appendChild(tdTitle);

        flipValues[i].forEach((val, j) => {
            let td = document.createElement('td');
            td.textContent = val.toFixed(2);
            if (val > naiveValues[j]) {
                td.classList.add('cell-highlight');
                td.title = `Naive: ${naiveValues[j].toFixed(3)}`;
            }
            tr.appendChild(td);
        });
        tbody.appendChild(tr);
    });

    // --- Chart 5: Sektörel Karşıt-Test ---
    const ctxSectoral = document.getElementById('chartSectoral').getContext('2d');
    new Chart(ctxSectoral, {
        type: 'bar',
        data: {
            labels: ['AKGRT', 'ANSGR', 'RAYSG', 'TURSG', 'AGESA', 'KCHOL', 'DOHOL', 'ALARK', 'ENKAI', 'SAHOL'],
            datasets: [{
                label: 'Flip Acc - Naive Baseline',
                data: [0.012, 0.009, 0.051, -0.058, -0.039, -0.017, -0.031, -0.011, -0.015, 0.009],
                backgroundColor: [
                    '#ef4444', '#ef4444', '#ef4444', '#ef4444', '#ef4444', // Sigorta
                    '#3b82f6', '#3b82f6', '#3b82f6', '#3b82f6', '#3b82f6'  // Holding
                ],
                borderWidth: 0
            }]
        },
        options: {
            indexAxis: 'y',
            responsive: true, maintainAspectRatio: false,
            scales: { x: { ...darkGrid }, y: darkGrid }
        }
    });

    // --- Chart 6: Asimetri Radar ---
    const ctxAsym = document.getElementById('chartAsymmetry').getContext('2d');
    new Chart(ctxAsym, {
        type: 'polarArea',
        data: {
            labels: ['THYAO DL', 'THYAO ML', 'GARAN DL', 'GARAN ML', 'AAPL DL', 'AAPL ML'],
            datasets: [{
                label: 'Anti-Prediktif Oranı (%)',
                data: [97, 0, 47, 0, 0, 0],
                backgroundColor: [
                    'rgba(239, 68, 68, 0.7)',  // THYAO DL - Yüksek Anti-pred
                    'rgba(16, 185, 129, 0.7)', // THYAO ML
                    'rgba(245, 158, 11, 0.7)', // GARAN DL - Rastgele
                    'rgba(59, 130, 246, 0.7)', // GARAN ML
                    'rgba(139, 92, 246, 0.7)', // AAPL DL
                    'rgba(6, 182, 212, 0.7)'   // AAPL ML
                ],
                borderWidth: 1,
                borderColor: '#0b0f19'
            }]
        },
        options: {
            responsive: true, maintainAspectRatio: false,
            scales: { r: { grid: { color: 'rgba(255,255,255,0.1)' }, angleLines: { color: 'rgba(255,255,255,0.1)' } } }
        }
    });

    // --- Gallery Population ---
    const galleryGrid = document.getElementById('galleryGrid');
    const imageNames = [
        "01_Sektorel_Kiyaslama_Bar.png",
        "02_Anti_Prediktif_Scatter.png",
        "03_Correlation_Drift_Slope.png",
        "04_Feature_Ablation_Bar.png",
        "05_MC_Tuzagi_Cozumu.png",
        "06_Mimari_Kiyaslama.png",
        "07_WalkForward_Tutarsizlik.png",
        "08_Piyasa_Hassasiyet_Heatmap.png",
        "09_AntiPredictive_ROC_Curve.png",
        "10_Sektorel_Sıkı_Kriter_Bar.png",
        "11_Korelasyon_Paradoksu.png",
        "12_Walkforward_Inconsistency.png",
        "13_Seed_Invariance_Bulgusu.png",
        "14_AAPL_Klasik_ML_Karsilastirma.png",
        "15_IN_LEN_Ablasyonu.png",
        "16_WalkForward_MultiArch_Heatmap.png",
        "17_Sigorta_v1_vs_v2_Seed.png"
    ];

    imageNames.forEach(img => {
        const div = document.createElement('div');
        div.className = 'gallery-item glass';
        div.innerHTML = `<img src="../../Gorseller/${img}" alt="${img}">`;
        div.onclick = () => openLightbox(img);
        galleryGrid.appendChild(div);
    });

    // Lightbox Logic
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightboxImg');
    const captionText = document.getElementById('caption');
    const closeBtn = document.querySelector('.close-btn');

    function openLightbox(imgName) {
        lightbox.style.display = "block";
        lightboxImg.src = `../../Gorseller/${imgName}`;
        captionText.innerHTML = imgName.replace(/_/g, ' ').replace('.png', '');
    }

    closeBtn.onclick = () => { lightbox.style.display = "none"; }
    
    // Glossary Logic
    const glossaryBtn = document.getElementById('glossaryBtn');
    const glossaryModal = document.getElementById('glossaryModal');
    const closeGlossary = document.getElementById('closeGlossary');

    glossaryBtn.onclick = () => { glossaryModal.style.display = "block"; }
    closeGlossary.onclick = () => { glossaryModal.style.display = "none"; }
    
    // Global click listener for modals
    window.onclick = (e) => { 
        if(e.target === lightbox) lightbox.style.display = "none"; 
        if(e.target === glossaryModal) glossaryModal.style.display = "none";
    }
});

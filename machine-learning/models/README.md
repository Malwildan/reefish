# Artefak model lokal

Folder ini disediakan untuk bobot, checkpoint, dan metadata model yang kelak disetujui untuk penggunaan bersama. Saat ini tidak ada bobot atau checkpoint yang dilacak di sini. Notebook `../notebooks/EDA_Clustering.ipynb` memasang MiniBatchKMeans pada runtime ketika dijalankan, tetapi tidak menyediakan artefak persisten atau layanan inferensi.

Sebelum sebuah model dipakai bersama, catat pemilik, tujuan/batas penggunaan, sumber dan izin data, versi kode/artefak, lisensi, format input/output, cara memperoleh artefak, serta hasil evaluasi terhadap baseline. Jangan menaruh data privat, kredensial, data pengguna, bobot, atau checkpoint ke Git.

Backend saat ini memberi label rekomendasi Go sebagai `is_fallback: true` dengan `model_version: heuristic-0.1`. Label tersebut adalah heuristik, bukan keluaran notebook clustering. Klaim performa atau manfaat hanya boleh dibuat setelah evaluasi dapat diulang dan divalidasi.

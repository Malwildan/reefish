# Machine learning

Folder ini kini memuat notebook EDA dan eksperimen clustering, skrip audit/persiapan geodata, serta beberapa layer dan sampel data yang dilacak. Notebook menjalankan clustering saat dieksekusi, tetapi tidak menyimpan bobot model untuk layanan prediksi. Belum ada layanan inferensi ML atau integrasi live; rekomendasi backend yang berjalan tetap heuristik Go berlabel `is_fallback: true`, `model_version: heuristic-0.1`.

## Bukti dan alur

- [Notebook EDA/clustering](notebooks/README.md) memuat EDA, visualisasi, eksperimen MiniBatchKMeans lima kelompok, ringkasan profil, skor silhouette sampel, dan ekspor titik GeoJSON. Notebook juga memiliki rancangan eksperimen KMeans lain yang belum dieksekusi. Input yang dipakai pada output notebook bukan bagian dari data yang dilacak; lihat batas reproduksinya di README notebook.
- [Utilitas geodata](src/README.md) mengaudit struktur, rentang numerik, geometri, cakupan area, serta keselarasan grid dan menyiapkan aset turunan. Ini pemeriksaan teknis, bukan validasi ilmiah.
- [Data](data/README.md) berisi beberapa CSV layer dan data geospasial yang dilacak. Unit, provenance, definisi kelas, atau izin sebagian berkas belum terverifikasi; lihat inventaris dan batas di README data.
- [Model](models/README.md) belum berisi bobot/checkpoint yang dapat digunakan ulang. [Pengujian](tests/README.md) belum menetapkan test runner atau suite evaluasi ML.

Grid memakai EPSG:32749, sel 500 m, dengan 31.354 indeks sel. Kontrak dan vektor bersama berada di `../contracts/grid-index.md` dan `../contracts/fixtures/grid-index-vectors.json`. Dataset potensi ikan tidak boleh diasumsikan identik dengan `potential_score`; hasil pembandingan yang tercatat menunjukkan ketidakcocokan.

## Interpretasi hasil dan demo

Skor silhouette 0.3617 yang tertanam di output notebook dihitung pada sampel 3.000 baris untuk mengevaluasi pemisahan cluster, bukan akurasi prediksi atau bukti manfaat ekologis. Level cluster lima kelas dirangking menurut rata-rata `potential_score` pada dataset yang dipakai dan bersifat relatif terhadap data tersebut; itu bukan label kualitas habitat yang tervalidasi.

Demo penilaian dapat memperlihatkan input yang benar-benar dipakai, sel EDA, metode preprocessing/clustering, visualisasi, ekspor, dan batas interpretasi. Untuk reproduksi, samakan versi data/kode dan lingkungan; jangan mengandalkan output tersimpan sebagai bukti bahwa inputnya tersedia di repo. Klaim dampak, akurasi, atau manfaat nelayan memerlukan ground truth, evaluasi terpisah, provenance/unit yang jelas, peninjauan ahli, dan validasi lapangan.

Data dan sampel tertentu sekarang memang terlacak di Git; jangan menambahkan data privat/lapangan tanpa izin, kredensial, data pengguna, bobot, checkpoint, atau keluaran build. Catat provenance dan aturan distribusi setiap artefak sebelum rilis.

# Notebook ML dan clustering

`EDA_Clustering.ipynb` adalah notebook Python yang ditujukan untuk Google Colab. Notebook memuat EDA, visualisasi spasial, eksperimen clustering, ringkasan profil, dan ekspor hasil per periode. Sebagian sel memiliki output tersimpan; output itu berasal dari input eksternal yang tidak disertakan bersama notebook.

## Analisis yang ada

Sel clustering utama memakai `MiniBatchKMeans` dengan lima cluster dan fitur `sst`, `chlor_a`, `depth_m`. Nilai kosong diimputasi median, `chlor_a` dan `depth_m` ditransformasi `log1p`, lalu fitur distandardisasi. Cluster diurutkan menjadi level 1–5 berdasarkan rata-rata `potential_score` pada data yang dimasukkan. Kode menghitung silhouette pada sampel acak 3.000 baris dan membuat visualisasi serta ekspor GeoJSON per periode. Output tersimpan menunjukkan skor silhouette 0.3617 pada sampel tersebut dan 752.496 baris/24 periode untuk run yang terekam.

Sel lain berisi eksperimen KMeans untuk kombinasi fitur E0/E1/E2 dan k 2–6 yang membandingkan silhouette, serta analisis ZPI/cluster. Sel-sel ini memiliki `execution_count` kosong; jangan menyatakan bahwa hasil eksperimen tersebut telah dijalankan.

Silhouette mengukur pemisahan cluster pada fitur yang digunakan; ia bukan akurasi terhadap ground truth, bukan validasi nilai ekologi, dan bukan bukti dampak konservasi. Level 1–5 adalah urutan relatif rerata `potential_score` dari dataset input, bukan kelas habitat tervalidasi. Notebook melakukan fit ketika sel clustering dijalankan; tidak ada bobot persisten atau layanan inference yang dihubungkan ke backend/aplikasi.

## Batas reproduksi

Notebook memakai Google Colab/Drive dan beberapa jalur input berbeda, termasuk `/content/drive/MyDrive/JOINTS/fixdataset.csv`, `/content/fixbangetdataset.csv`, `/mnt/data/dataset1 - dataset1.csv`, atau upload manual. Nama/path tersebut tidak menunjuk pada satu berkas input yang dilacak di repo, dan CSV 752.496 baris yang dipakai oleh output clustering tidak tersedia di `machine-learning/data/`. Untuk reproduksi, tentukan satu input berizin yang sesuai schema notebook, ubah jalur dengan sengaja, dan simpan catatan versi/hash di luar data privat.

Notebook mengimpor pandas, NumPy, scikit-learn, Matplotlib, Seaborn, Plotly, Folium, dan modul Colab/IPython; sel utama dapat memasang beberapa paket lewat `pip` saat runtime. Dependensi notebook ini belum dipin dalam requirements khusus. `src/geodata_prep/requirements.txt` hanya untuk skrip audit geodata, bukan lingkungan lengkap notebook. Notebook juga menyertakan gambar inline berbasis data dan output tersimpan; tinjau ukuran serta provenance sebelum perubahan atau distribusi.

Demo yang dapat dinilai perlu menunjukkan sumber input, versi lingkungan, langkah preprocessing, pengaturan cluster, silhouette dan keterbatasannya, serta artefak ekspor. Evaluasi yang lebih kuat memerlukan baseline, uji kestabilan, pemisahan spasial/waktu, pembandingan dengan label lapangan, dan tinjauan domain. Jangan sertakan data privat, kredensial, atau artefak runtime sensitif.

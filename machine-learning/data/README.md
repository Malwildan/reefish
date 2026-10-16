# Data ML dan geospasial

Sebagian data kini dilacak di folder ini; dataset input notebook dan sejumlah sumber/hasil audit tetap tidak tersedia dalam Git. Inventaris di bawah hanya menjelaskan berkas yang terverifikasi. Nama, kolom, atau hash tidak menetapkan provenance, izin, unit, waktu observasi, ataupun makna ilmiah. Periksa sumber dan aturan distribusi sebelum penggunaan publik.

## Berkas yang dilacak

```text
coral_reef_samples.csv       18 baris; longitude, latitude, reef_mask, geomorphic, benthic
kedalaman_laut.csv           31.354 baris; grid_x, grid_y, latitude, longitude, value
potensi_ikan.csv             31.354 baris; grid_x, grid_y, latitude, longitude, value
suhu_laut.csv                31.354 baris; grid_x, grid_y, latitude, longitude, value
mangrove_2023_jatim.geojson  3 fitur
```

Arti label/kolom pada sampel terumbu, sumber dan lisensi tiap layer, unit `value`, serta tanggal/metode pengambilan data belum dapat dipastikan dari berkas saja. File `klorofil_a.csv` berisi 752.496 baris yang dipakai pada audit/notebook sebelumnya tidak termasuk daftar berkas terlacak saat ini. Begitu pula CSV 752.496 baris dengan kolom `period`, `grid_id`, `sst`, `chlor_a`, `depth_m`, dan `potential_score` yang tercermin dalam output clustering notebook tidak tersedia di repo.

## Hasil turunan dan pemakaian

`processed/`, `geojson/`, dan laporan/manifest yang disebut pada catatan audit lokal adalah hasil turunan, bukan berkas terlacak yang terdaftar di atas. Notebook mengekspor cluster GeoJSON dan metadata saat dijalankan dengan inputnya; output tersimpan di notebook bukan pengganti input atau ekspor yang dapat diulang. Audit `src/geodata_prep/audit_prepare.py` juga memerlukan set sumber lengkap sesuai nama yang diharapkan script, termasuk sumber coral GeoJSON dan CSV klorofil; empat file layer terlacak saja tidak cukup untuk mengulangnya.

Untuk menyiapkan aset contoh peta Flutter, audit menghasilkan aset di folder output yang ditentukan. Salin berkas yang diperlukan secara manual ke `frontend/mobile/examples/peta_laut/assets/geodata/`; audit tidak menyalinnya otomatis. GeoJSON cluster dapat diproses oleh `backend/scripts/geojson_to_csv.py` untuk impor, setelah schema, sumber, dan maknanya diverifikasi.

Perintah dan dependensi audit tersedia di [README kode sumber](../src/README.md). Siapkan salinan input dengan nama persis yang diharapkan skrip, termasuk `coralreef(1).geojson` dan `kedalaman_laut (1).csv`; jangan mengubah sumber asli. Gunakan direktori input/output terpisah yang tidak saling bersarang. Langkah menjalankan contoh Flutter ada di [README contoh peta](../../frontend/mobile/examples/peta_laut/README.md).

## Temuan audit terdahulu

Catatan audit 16-10-2026 menyebut pengulangan skrip saat itu menghasilkan berkas coral, mangrove, 24 blok klorofil, dan manifest yang identik byte-per-byte dengan folder `processed/geodata/` lokal; rincian laporan klorofil tersimpan lebih lengkap daripada yang dikeluarkan skrip. Berkas hasil tersebut tidak tercatat sebagai bagian dari inventaris Git di atas.

Dalam pembandingan numerik terhadap output cluster yang saat itu tersedia, setiap blok klorofil cocok dengan `chlor_a` periode `2024-01` sampai `2025-12` untuk semua 752.496 baris; `suhu_laut.csv` cocok dengan `sst` periode `2025-12`, dan `kedalaman_laut.csv` dengan `depth_m` pada semua periode. `potensi_ikan.csv` tidak cocok dengan `potential_score` periode `2024-01` dan `2025-12`. Ini adalah kesesuaian data yang pernah diperiksa, bukan verifikasi provenance/unit atau jaminan bahwa dataset lama tersedia dalam checkout sekarang.

## Grid kanonis

Layer dan `grid_cells` backend memakai EPSG:32749, sel 500 m, origin kiri bawah `(637500, 8988000)`, `grid_x` 1..187 ke timur, `grid_y` 1..177 ke utara (31.354 sel). ID backend berbentuk `X{grid_x:03}_Y{grid_y:03}`. Formula dan vektor uji ada di [`../../contracts/grid-index.md`](../../contracts/grid-index.md) dan [`../../contracts/fixtures/grid-index-vectors.json`](../../contracts/fixtures/grid-index-vectors.json).

Demo data harus menampilkan sumber, izin, unit, waktu, dan batas kualitas yang dapat dibuktikan. Jangan menyimpulkan kesehatan habitat, potensi tangkapan, dampak konservasi, atau akurasi model hanya dari schema, warna peta, atau pengelompokan tanpa label.

# Contoh peta laut

Folder ini berisi aplikasi Flutter mandiri untuk mengeksplorasi layer dan geometri. Ia tidak memakai alur auth, Journey, atau repository backend aplikasi utama; untuk demo terintegrasi, ikuti [README mobile](../../README.md#demo-lokal).

## Menjalankan contoh mandiri

Contoh mengharuskan aset data lokal, yang tidak dilacak Git. Siapkan dataset sesuai petunjuk di [README data ML](../../../../machine-learning/data/README.md) atau jalankan audit ke folder output terpisah lebih dulu. Dari root repo PowerShell, buat proyek baru dan salin kode serta dependency contoh:

```powershell
flutter create marine_map_demo
Copy-Item frontend/mobile/examples/peta_laut/lib/* marine_map_demo/lib -Recurse -Force
Copy-Item frontend/mobile/examples/peta_laut/pubspec.yaml marine_map_demo/pubspec.yaml -Force
New-Item -ItemType Directory -Force marine_map_demo/assets/geodata/klorofil_a
Copy-Item machine-learning/data/processed/geodata/coral.geojson,machine-learning/data/processed/geodata/mangrove.geojson -Destination marine_map_demo/assets/geodata/
Copy-Item machine-learning/data/processed/geodata/klorofil_a/* -Destination marine_map_demo/assets/geodata/klorofil_a/
Copy-Item machine-learning/data/raw/layers/potensi_ikan.csv,machine-learning/data/raw/layers/suhu_laut.csv,machine-learning/data/raw/layers/kedalaman_laut.csv -Destination marine_map_demo/assets/geodata/
Set-Location marine_map_demo
flutter pub get
flutter analyze
flutter run
```

Jalankan perintah di direktori proyek baru `marine_map_demo` setelah `Set-Location`. Gunakan Flutter stable yang membawa Dart minimal 3.10.1. Ubah `userAgentPackageName` di layer tile dan pastikan permission Internet ada pada Android build release. Untuk pengukuran rendering, gunakan profile mode pada perangkat target; browser atau debug mode bukan hasil performa native.

## Data dan batas interpretasi

Contoh menampilkan coral kode 1 dengan label sementara, mangrove 2023, nilai potensi ikan, suhu, kedalaman, dan satu pilihan dari 24 entri klorofil. Grid berukuran 500 m pada EPSG:32749. Nilai klorofil ditampilkan berdasarkan urutan ekspor, bukan tanggal; meskipun audit numerik menunjukkan kecocokan terhadap keluaran periode bulanan, pemetaan waktu dan provenance sumber belum disahkan untuk label aplikasi. Satuan sejumlah CSV dan kamus kelas coral belum dikonfirmasi.

Warna mengikuti rentang snapshot, bukan ambang ilmiah atau rekomendasi tangkap. Tile OSM memerlukan jaringan dan tidak boleh diunduh massal dari server publik. Grid adalah indeks, bukan mask perairan atau navigasi. Tampilan contoh tidak membuktikan backend, autentikasi, lock aktif, sinkronisasi offline, atau dampak lapangan.

Panduan lengkap tentang audit, schema, dan ketentuan peta ada di [panduan Flutter peta laut v2](../../../../docs/frontend/panduan-implementasi-flutter-peta-laut-v2.md). Lihat [audit data laut](../../design/marine/README.md) untuk manifest dan validasi.
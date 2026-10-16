# Data laut: audit dan batas interpretasi

Folder ini menyimpan manifest data laut yang dibundel di aplikasi, hash file, dan laporan validasi numerik/spasial: `bundled-data-manifest.json`, `SHA256SUMS.json`, dan `validation_report.json`. Berkas ini mendukung pemeriksaan integritas terhadap snapshot yang dipakai aplikasi. Ia tidak membuktikan lisensi distribusi atau validitas ilmiah.

Aplikasi utama membaca snapshot lewat `AssetMarineRepository`. Data numerik, habitat, dan identitas sel disatukan pada grid analitik tetap 500 m (EPSG:32749). Nilai yang tidak punya baris sumber tetap NoData. Layer klorofil memiliki 24 urutan ekspor; nomor urut bukan tanggal atau bulan, sehingga data tidak digabung menjadi satu nilai dan tidak diberi label waktu.

Pada integrasi demo yang tercatat, hanya periode sumber `2025-12` yang diimpor ke backend untuk layer prediksi. Itu data historis dan bukan observasi kondisi laut terkini. Satuan sumber CSV dan kamus kelas coral belum terkonfirmasi. Atribut luas habitat mengacu pada geometri sumber; irisan dengan sel tidak membuktikan tutupan atau ketiadaan habitat di lapangan.

Peta menggunakan dua sumber dengan peran berbeda: backend Supabase menyediakan layer/habitat dan kebijakan saat tersedia, sedangkan snapshot lokal menjadi fallback yang ditandai ketika layer backend tidak tersedia. Kegagalan permintaan periode chlorophyll tidak diganti diam-diam dengan snapshot lama. Status lock tetap diperiksa melalui repository kebijakan terautentikasi; cache layer tidak menggantikan pemeriksaan ini.

Basemap OpenStreetMap adalah konteks visual online. Grid bukan garis pantai, wilayah administrasi, zona konservasi, atau grafik navigasi. Routing proyek ditandai simulasi dan tidak boleh dipakai sebagai arahan keselamatan.

Untuk membaca interaksi popup dan batas QA lihat [QA popup](../../qa/map-popup/README.md). Untuk pengukuran pemilihan sel lihat [benchmark](../../qa/selection-performance/README.md). Untuk konteks dataset paket awal lihat [panduan implementasi peta laut v2](../../../../docs/frontend/panduan-implementasi-flutter-peta-laut-v2.md) dan [laporan integrasi demo](../../../../docs/frontend/hackathon-integration.md).

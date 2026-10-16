# Supabase

Backend grid **statis 500 × 500 meter** diterapkan melalui Supabase MCP ke proyek **REEFISH** (`upyahsecuorqghcghflg`) pada 16 Oktober 2026, sesuai resolusi dataset pelatihan yang ditentukan pengguna. Riwayat migrasi:

- `20261016000020_dynamic_grid_definitions.sql`: PostGIS, definisi grid immutable, snapshot, pembatasan berbasis geometri, audit, dan RPC admin.
- `20261016000217_grid_access_guards.sql`: kebijakan deny untuk akses tabel langsung dan indeks foreign key.
- `20261016001628_restore_fixed_500m_grid.sql`: membatalkan grid dinamis, menghapus draft 1 km, menghapus RPC perubahan ukuran, dan memberlakukan constraint 500 m tetap.

Nama file lokal mengikuti versi yang dicatat MCP dalam riwayat migrasi hosted. File awal dibuat memakai Supabase CLI 2.121.0, lalu namanya diselaraskan dengan riwayat tersebut. Jangan menerapkan ulang migrasi yang sudah tercatat.

Area `east-java-pilot` hanya memakai grid 500 m dengan identitas awal yang sama. Admin mendatang hanya dapat me-lock atau membuka lock petak melalui `set_grid_lock`; ukuran tidak dapat diganti melalui RPC. Tidak ada admin atau pembatasan nyata yang di-seed. Keanggotaan admin baru ditentukan nanti. Panel admin belum dibuat.

Client memanggil `get_grid_lock_snapshot` memakai sesi Supabase Auth. Tabel tidak diberi akses langsung; implementasi RPC berada di schema `reefish_private`, memeriksa identitas serta membership admin, dan memakai search path tetap. `validate_fishing_grid_selection` harus dipanggil dalam transaksi yang sama dengan endpoint penyimpanan lokasi menangkap ikan mendatang.

Kontrak lengkap ada di `../../contracts/grid-locks.md`. Pengujian `tests/fixed_grid.sql` berhasil di hosted project dan seluruh fixture di-rollback. Bukti uji desain dinamis yang sudah dibatalkan berada di `archive/`; jangan menjalankannya sebagai pengujian kondisi saat ini. Riwayat migrasi yang sudah diterapkan dipertahankan agar replay menghasilkan skema statis yang sama. Kredensial, publishable key lokal, dan secret tidak disimpan dalam folder ini.

## Journey backend — status hosted 16 Oktober 2026

Enam migrasi asli `20261016100000_schema.sql` sampai `20261016100500_nelayan.sql` telah diterapkan dalam satu transaksi, diikuti transaksi migrasi kompatibilitas maju `20261016100550` pada proyek `upyahsecuorqghcghflg`. Migrasi fixed-grid tiga file di atas tetap menjadi riwayat hosted dan tidak dijalankan ulang. Migrasi Journey menambahkan profil, sinkronisasi nomor dari Supabase Auth, kapal, perjalanan, titik perjalanan, policy RLS, serta RPC; tidak mengganti definisi atau lock grid tetap.

Satu profil dibuat untuk akun Auth yang sudah ada lewat backfill. Role yang tersimpan tidak diubah, dan provider Auth phone/password tetap memakai pengaturan yang ada. Import titik `grid_cells` berisi 31.354 ID dan koordinat dari GeoJSON pengguna dengan seluruh 24 periodenya; manifest dan hash koordinat tersimpan di `setup/journey-grid-cells.manifest.json`.

`api_me`, `api_create_boat`, `api_post_trip`, `api_list_trips`, dan `api_trip_detail` kini tersedia. Akses anonim ditolak; fungsi memeriksa identitas dan kepemilikan data. `tests/journey_live.sql` berhasil dijalankan dengan claim JWT authenticated dan semua fixture di-rollback. Pemeriksaan akhir database menunjukkan satu user Auth dan satu profile, tanpa boat atau trip. Detail dan batas bukti ada di `../../frontend/mobile/design/journey/backend-audit.md`.

Deployment ini berhenti pada dukungan Journey. Migrasi `20261016100600` dan sesudahnya belum diterapkan. Go API belum di-deploy/dikonfigurasi, dan prediksi belum diimpor; rekomendasi dan forecast belum tersedia. Untuk migrasi selanjutnya, gunakan Supabase CLI dan baca `supabase migration --help` dari CLI yang terpasang sebelum memilih perintah. Jangan mengubah atau menerapkan ulang tiga migrasi fixed-grid yang sudah tercatat.

Dua marker hosted MCP (`20261016091612`, `20261016091944`) juga dicatat pada file migrasi lokal sebagai no-op. Versi pertama mewakili eksekusi atomik enam migrasi sumber; versi kedua mewakili transaksi kompatibilitas yang terpisah. SQL sumber tetap berada pada versi aslinya agar fresh replay menjalankannya sesudah marker, dan ledger hosted menandainya sudah diterapkan. Jangan menyalin ulang bundle hosted sebagai migrasi baru.

Digest koordinat kanonis lokal dan remote cocok: `7e3375cc745ccc17d97774c6db43d759`. Manifest sumber/CSV berada di `setup/journey-grid-cells.manifest.json`; bukti deployment dan digest remote ada di `tests/journey-live-verification.json`. CSV dan batch SQL import merupakan artefak lokal yang di-ignore, bukan dataset prediksi.

Migrasi, test, dan panduan dari branch `gipar` (nelayan, zona/heatmap, layer ML) dijelaskan di `setup/README.md`. Sistem grid lock di atas dan zona `gipar` saat ini berjalan berdampingan, sampai tim memutuskan model pembatasan.

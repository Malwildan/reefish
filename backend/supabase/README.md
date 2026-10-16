# Supabase

Backend grid **statis 500 × 500 meter** diterapkan melalui Supabase MCP ke proyek **REEFISH** (`upyahsecuorqghcghflg`) pada 16 Oktober 2026, sesuai resolusi dataset pelatihan yang ditentukan pengguna. Riwayat migrasi:

- `20261016000020_dynamic_grid_definitions.sql`: PostGIS, definisi grid immutable, snapshot, pembatasan berbasis geometri, audit, dan RPC admin.
- `20261016000217_grid_access_guards.sql`: kebijakan deny untuk akses tabel langsung dan indeks foreign key.
- `20261016001628_restore_fixed_500m_grid.sql`: membatalkan grid dinamis, menghapus draft 1 km, menghapus RPC perubahan ukuran, dan memberlakukan constraint 500 m tetap.

Nama file lokal mengikuti versi yang dicatat MCP dalam riwayat migrasi hosted. File awal dibuat memakai Supabase CLI 2.121.0, lalu namanya diselaraskan dengan riwayat tersebut. Jangan menerapkan ulang migrasi yang sudah tercatat.

Area `east-java-pilot` hanya memakai grid 500 m dengan identitas awal yang sama. Admin mendatang hanya dapat me-lock atau membuka lock petak melalui `set_grid_lock`; ukuran tidak dapat diganti melalui RPC. Tidak ada admin atau pembatasan nyata yang di-seed. Keanggotaan admin baru ditentukan nanti. Panel admin belum dibuat.

Client memanggil `get_grid_lock_snapshot` memakai sesi Supabase Auth. Tabel tidak diberi akses langsung; implementasi RPC berada di schema `reefish_private`, memeriksa identitas serta membership admin, dan memakai search path tetap. `validate_fishing_grid_selection` harus dipanggil dalam transaksi yang sama dengan endpoint penyimpanan lokasi menangkap ikan mendatang.

Kontrak lengkap ada di `../../contracts/grid-locks.md`. Pengujian `tests/fixed_grid.sql` berhasil di hosted project dan seluruh fixture di-rollback. Bukti uji desain dinamis yang sudah dibatalkan berada di `archive/`; jangan menjalankannya sebagai pengujian kondisi saat ini. Riwayat migrasi yang sudah diterapkan dipertahankan agar replay menghasilkan skema statis yang sama. Kredensial, publishable key lokal, dan secret tidak disimpan dalam folder ini.


Migrasi, test, dan panduan dari branch `gipar` (nelayan, zona/heatmap, layer ML) dijelaskan di `setup/README.md`. Sistem grid lock di atas dan zona `gipar` saat ini berjalan berdampingan, sampai tim memutuskan model pembatasan.

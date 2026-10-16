# Pengujian Supabase

`fixed_grid.sql` berisi smoke test SQL biasa yang telah dijalankan melalui Supabase MCP `execute_sql` setelah migrasi pemulihan grid statis pada proyek REEFISH. Test memakai transaksi dan selalu diakhiri `ROLLBACK`; fixture akun, membership admin, dan lock tidak tersimpan.

Script mengasumsikan seed pilot awal (versi area 1, hanya grid 500 m, tanpa pembatasan). Jalankan hanya pada lingkungan pengujian yang memenuhi prasyarat itu. Pemeriksaan mencakup snapshot lima field, geometri 500 × 500 meter, constraint yang menolak ukuran lain, ketiadaan RPC grid dinamis, lock/unlock, versi stale, validasi lokasi, dan penolakan akses non-admin.

`journey_live.sql` adalah integration test rollback-only untuk backend Journey. Test ini telah dijalankan setelah migrasi `20261016100000`–`20261016100550` dan import `grid_cells` pada hosted project. Ia memeriksa role default meski metadata signup meminta `konservatif`, `api_me`, pembuatan kapal, perjalanan onboarding, replay `client_trip_id`, history/detail, penolakan write langsung, RLS per akun, dan penolakan detail milik akun lain. Test memakai dua akun fixture dan mengakhiri transaksi dengan `ROLLBACK`; hasil live run tidak meninggalkan akun, kapal, atau perjalanan fixture. Akun yang sudah ada tetap satu profile tanpa kapal/perjalanan.

Jalankan hanya pada database uji atau dengan pemahaman bahwa test memasukkan dua baris sementara ke `auth.users`. Test memerlukan `grid_cells` yang sudah diimpor dan sengaja tidak memanggil endpoint rekomendasi/heatmap karena migrasi lanjutan belum diterapkan.

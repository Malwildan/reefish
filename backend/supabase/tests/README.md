# Pengujian Supabase

`fixed_grid.sql` berisi smoke test SQL biasa yang telah dijalankan melalui Supabase MCP `execute_sql` setelah migrasi pemulihan grid statis pada proyek REEFISH. Test memakai transaksi dan selalu diakhiri `ROLLBACK`; fixture akun, membership admin, dan lock tidak tersimpan.

Script mengasumsikan seed pilot awal (versi area 1, hanya grid 500 m, tanpa pembatasan). Jalankan hanya pada lingkungan pengujian yang memenuhi prasyarat itu. Pemeriksaan mencakup snapshot lima field, geometri 500 × 500 meter, constraint yang menolak ukuran lain, ketiadaan RPC grid dinamis, lock/unlock, versi stale, validasi lokasi, dan penolakan akses non-admin.

`nelayan.sql`, `zones_heatmap.sql`, dan `layers.sql` (branch `gipar`) juga memakai transaksi + `ROLLBACK`. Jalankan setelah import data grid; urutan dan prasyarat ada di `../setup/README.md`.

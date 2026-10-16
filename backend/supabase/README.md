# Supabase Reefish

Supabase menyediakan Postgres/PostGIS, autentikasi, RLS, RPC nelayan dan konservatif, grid/lock, zona, heatmap, serta layer ML dan habitat. Source skema yang dapat ditinjau adalah `migrations/*.sql`; kontrak publik lintas aplikasi ada di [`../../contracts/`](../../contracts/).

## Status dan bukti hosted

Rekap bertanggal 16 Oktober 2026 mencatat migrasi zona/heatmap, layer, lock rehab, dukungan antrean push, optimasi konteks rekomendasi, dan refresh asinkron telah diterapkan pada proyek REEFISH. Pemeriksaan integrasi mencatat 31.354 sel layer untuk satu periode sumber (`2025-12`), 140 fitur karang, tiga mangrove, pemeriksaan SQL rollback lulus, dan RLS aktif di tabel publik yang diperiksa. Lihat [`setup/integration-verification.json`](setup/integration-verification.json) untuk rincian dan batas bukti.

Itu merupakan laporan hasil pada waktu tersebut, bukan status live yang terus diperbarui. Jangan menjalankan ulang bundle `hosted_setup.sql` pada proyek berisi data atau menerapkan ulang migrasi historis. Gunakan [panduan setup](setup/README.md) setelah memeriksa ledger dan prasyarat target.

## Demo yang dapat ditunjukkan

- RPC `api_layers` dan `api_habitat` memasok layer peta; missing value tetap NoData dan data yang diimpor untuk demo hanya periode 2025-12.
- Zona `rehab` tercermin pada snapshot grid lock sehingga sel tetap terlihat tetapi tidak dapat dipilih untuk menangkap ikan.
- Dashboard menggunakan heatmap fatigue, pressure, CPUE, dan zona. Refresh administratif mengantrekan pekerjaan; worker `pg_cron` memprosesnya.
- `push-dispatch` memiliki implementasi pengiriman FCM, tetapi laporan integrasi menyatakan kredensial/proyek Firebase dan registrasi notifikasi mobile belum dikonfigurasi. Keberadaan kode bukan bukti push terkirim.

Smoke test tiap domain dan bukti pelaksanaannya dirangkum di [`tests/README.md`](tests/README.md). Uji tersebut tidak menggantikan uji pengguna akhir atau pemeriksaan lapangan.

# Tes dan bukti Supabase

Tes SQL menguji kebijakan dan RPC pada database nyata. Berkas dengan transaksi `ROLLBACK` menghapus fixture di akhir, tetapi selama berjalan tetap membuat baris sementara pada `auth.users`; jalankan pada lingkungan uji yang sesuai dan ikuti prasyarat di [`../setup/README.md`](../setup/README.md).

## Tes saat ini

| Berkas | Cakupan dan prasyarat |
|---|---|
| `fixed_grid.sql` | Constraint grid 500 m, snapshot lock, validasi pemilihan, versi stale, dan batas admin. Perlu skema grid/lock. |
| `journey_live.sql` | Authenticated role, profil, kapal, trip, idempotensi, history/detail, RLS dan isolasi akun. Perlu migrasi Journey dan `grid_cells`. |
| `nelayan.sql` | RPC profil/kapal/trip nelayan; perlu impor grid dan migrasi nelayan. |
| `zones_heatmap.sql` | Zona/kuota, heatmap, flags, lock rehab dan refresh; perlu data grid dan migrasi zona. |
| `layers.sql` | Layer ML dan habitat; perlu impor tabel prediksi, layer, karang, serta mangrove. |

## Hasil yang tercatat

`verification-fixed500.json` merekam `fixed_grid.sql` lulus setelah pemulihan grid tetap dan fixture di-rollback. `journey-live-verification.json` merekam uji Journey hosted lulus, termasuk isolasi akun dan larangan write langsung; file itu juga menyatakan prediksi belum diimpor pada fase tersebut. Rekap yang lebih baru, [`../setup/integration-verification.json`](../setup/integration-verification.json), mencatat tes Journey, zona, dan layer untuk integrasi 16 Oktober 2026 lulus dengan fixture rollback.

Hasil tersebut adalah bukti yang berbeda dari laporan implementasi: SQL rollback menguji aturan backend dan integrasi endpoint, bukan tampilan peta, keberhasilan push di perangkat, keselamatan rute, atau dampak tangkapan di lapangan. Jangan menjalankan tes arsip dinamis sebagai verifikasi sekarang.

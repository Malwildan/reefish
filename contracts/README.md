# Kontrak bersama

Folder ini menyimpan definisi lintas backend, mobile, web, dan komponen data/ML supaya klien dapat bertukar data dengan bentuk serta aturan yang sama. Berkas kontrak adalah acuan integrasi; implementasi tetap harus diuji terhadapnya.

## Isi saat ini

- [Nelayan API](nelayan-api.openapi.yaml) — API data dan alur nelayan; implementasi Go terkait berada di [`backend/api/internal/usecase/nelayan/nelayan.go`](../backend/api/internal/usecase/nelayan/nelayan.go).
- [Map, zones, dan admin API](map-zones-api.openapi.yaml) — peta, zona konservasi, dan administrasi; lihat [migration zones/heatmap](../backend/supabase/migrations/20261016100600_zones_heatmap.sql) dan [migration lapisan ML](../backend/supabase/migrations/20261016100700_ml_layers.sql).
- [Route API](route-api.openapi.yaml) — permintaan dan respons perutean; implementasinya ada di [`backend/api/internal/usecase/planroute/plan.go`](../backend/api/internal/usecase/planroute/plan.go).
- [Grid index](grid-index.md) dan [fixture vektor](fixtures/grid-index-vectors.json) — aturan indeks grid 500 m dan vektor yang harus direproduksi oleh setiap klien. Implementasi referensi berada di [`backend/api/internal/domain/gridindex`](../backend/api/internal/domain/gridindex).
- [Grid locks](grid-locks.md) — format ID sel kanonis, snapshot kunci sel, aturan versi/kedaluwarsa, dan validasi pilihan; implementasi DB dirinci di [migration grid access guards](../backend/supabase/migrations/20261016000217_grid_access_guards.sql) dan [migration fixed grid](../backend/supabase/migrations/20261016001628_restore_fixed_500m_grid.sql).

Setiap perubahan lintas domain perlu memperbarui kontrak sebelum implementasi. Cantumkan pemilik, versi atau kompatibilitas, contoh valid, serta kasus gagal saat menambah kontrak. Gunakan JSON `snake_case`, koordinat GeoJSON `[longitude, latitude]` dalam EPSG:4326, dan bentuk error API yang konsisten dengan kontrak.

## Inovasi, implementasi, dan demo

Nilai kontribusi kontrak terlihat pada keputusan domain yang dapat digunakan bersama: identitas grid lintas klien, aturan lock/versi untuk mencegah pemilihan sel yang tidak sah, serta skema API yang menghubungkan produk. README ini mendokumentasikan permukaan integrasi, bukan membuktikan semua klien sudah mematuhi kontrak.

Demo integrasi yang kuat menjalankan fixture grid pada implementasi terkait, menunjukkan contoh request/response valid dan error, lalu memperlihatkan alur lintas aplikasi menggunakan data sintetis atau berizin. Untuk menilai kelayakan, tunjukkan pemilik kontrak, strategi kompatibilitas, autentikasi/otorisasi yang didefinisikan, serta bagaimana perubahan versi ditangani. Jangan masukkan payload produksi, data pribadi, token, atau rahasia sebagai fixture.

Kontrak API bukan bukti dampak lingkungan atau hasil model. Klaim dampak perlu dihubungkan dengan metrik dan data terverifikasi di luar spesifikasi antarmuka.

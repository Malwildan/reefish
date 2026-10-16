# Backend Reefish

Backend menggabungkan Supabase (Auth, Postgres/PostGIS, RLS, RPC, Edge Functions) dengan Go Gin untuk komputasi rute, rekomendasi, dan cuaca. Implementasi terhubung ke aplikasi nelayan dan dashboard konservatif; status tiap integrasi dan batas verifikasinya dicatat dalam [laporan integrasi hackathon](../docs/frontend/hackathon-integration.md) serta [rekap verifikasi hosted](supabase/setup/integration-verification.json).

## Alur demo dan bukti

1. Masuk sebagai nelayan di aplikasi, lihat layer ML/habitat dan status area; sel rehab tetap terlihat tetapi tidak dapat dipilih. Jalur ini memakai Supabase RPC dan kontrak grid bersama.
2. Tampilkan cuaca dan tiga rekomendasi dari Go API. Rekomendasi yang tersedia saat demo adalah fallback heuristik `heuristic-0.1`, bukan inferensi model atau janji hasil tangkapan.
3. Di dashboard konservatif, lihat heatmap, zona dan saran sistem; perubahan zona memengaruhi snapshot lock. Refresh heatmap berjalan lewat antrean dan worker `pg_cron`.

Laporan hosted mencatat pemeriksaan autentikasi/RPC, kueri API Railway, uji integrasi SQL rollback, dan status UI. Angka tersebut adalah hasil pemeriksaan pada 16 Oktober 2026, bukan jaminan uptime atau pengujian lapangan. APK belum diuji secara fisik; pengiriman push dan pengujian navigasi operasional belum diverifikasi.

## Struktur

| Area | Tanggung jawab dan titik masuk |
|---|---|
| [`api/`](api/README.md) | Go Gin: `POST /v1/routes`, rekomendasi, dan cuaca; mengautentikasi JWT Supabase. |
| [`supabase/`](supabase/README.md) | Skema, RLS, RPC nelayan/konservatif, heatmap, layer, dan function push-dispatch. |
| [`scripts/`](scripts/) | Validasi SQL dan persiapan impor layer dari data lokal. |
| [`../contracts/`](../contracts/) | Kontrak kanonis API rute, nelayan, peta/zona, dan grid. |

## Menjalankan dan memeriksa

Jalankan API lokal dari `backend/api` dengan variabel di `.env.example` (tidak dimuat otomatis), lalu `go run ./cmd/api`; `GET /health/live` memeriksa proses. Jalankan `go test ./...` untuk uji unit/integrasi Go. Migrasi dan uji SQL memiliki prasyarat data; ikuti [panduan setup Supabase](supabase/setup/README.md). CI backend menjalankan gofmt, vet, tes Go, format/cek Deno, dan parser SQL.

Untuk mengulang demo hosted, gunakan jalur akses yang sudah tersedia dan jangan menerapkan ulang migrasi dari README. Status migrasi, sumber data, dan batas integrasi dapat berubah; periksa file verifikasi bertanggal sebelum demo.

## Batas implementasi

Grid analitik adalah 500 m EPSG:32749 dan mengikuti kontrak ID bersama. Data layer yang diimpor untuk demo hanya periode sumber 2025-12; nilai historis dan unit/kode sumber yang belum terkonfirmasi tetap harus ditampilkan sebagai data berketidakpastian. Go menghitung rute simulasi, tetapi hasilnya belum menjadi navigasi laut operasional. Kunci service-role, kredensial, dan dataset tidak boleh masuk Git.

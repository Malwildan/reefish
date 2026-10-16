# Go API Reefish (`nelayan-route`)

Service Go Gin menangani komputasi di luar RPC database: simulasi rute pergi-pulang dan BBM (`POST /v1/routes`), rekomendasi (`GET /api/v1/recommendations`), serta cuaca titik/area (`GET /api/v1/weather`, `/api/v1/weather/area`). Selain `/health/live`, endpoint aplikasi memerlukan `Authorization: Bearer <Supabase access token>`; akses ke data Supabase memakai JWT pemanggil agar RLS tetap berlaku. Kontrak request dan response ada di [`contracts/route-api.openapi.yaml`](../../contracts/route-api.openapi.yaml) dan [`contracts/nelayan-api.openapi.yaml`](../../contracts/nelayan-api.openapi.yaml).

## Bukti demo dan batas hasil

API produksi untuk demo berjalan di [Railway](https://reefish-api-production.up.railway.app/health/live), dan laporan 16 Oktober 2026 mencatat health 200, cuaca terautentikasi 200 (2,42 detik), serta refresh rekomendasi 200 dengan tiga item (3,12 detik). Hasil rekomendasi berlabel fallback heuristik `heuristic-0.1`; ia bukan inferensi model ML. Source diunggah lewat CLI, sehingga perubahan lokal/GitHub belum otomatis menjadi deployment.

Endpoint rute menghasilkan simulasi berbasis graf grid dan zona; laporan integrasi menyatakan hasil itu belum aman sebagai navigasi operasional laut. Cuaca Open-Meteo dapat mengembalikan nilai `null` dekat pantai. Kode mempertahankan nilai tak tersedia dan menandai risiko `unknown`, bukan menggantinya dengan nol. Cuaca titik menerima `lat`, `lng`, dan `hours` (1–48; default 24); cache berada di memori proses selama 30 menit per sel sekitar 1 km.

## Lokal

```sh
cd backend/api
export SUPABASE_URL=http://127.0.0.1:54321
export SUPABASE_ANON_KEY='<anon atau publishable key dari supabase status>'
export ALLOWED_ORIGIN=http://localhost:3000
go run ./cmd/api
```

Di PowerShell gunakan `$env:SUPABASE_URL`, `$env:SUPABASE_ANON_KEY`, dan `$env:ALLOWED_ORIGIN`. Atur origin browser secara tepat; Flutter native tidak menggunakan CORS. Port lokal default `8080`. Dockerfile dapat dibangun dari direktori ini:

```sh
docker build -t reefish-api .
docker run -p 8080:8080 -e SUPABASE_URL=http://host.docker.internal:54321 -e SUPABASE_ANON_KEY='<key>' reefish-api
```

## Pemeriksaan teknis

`go test ./...` menjalankan uji unit dan handler, termasuk token wajib, validasi, penolakan akses, kegagalan provider, serta respons endpoint. CI menjalankan `gofmt`, `go vet`, dan tes Go. Untuk memperlihatkan alur di UI, jalankan aplikasi dengan base URL berakhiran `/api/v1` dan sesi Supabase yang valid; detail rute ada di [spesifikasi](../../docs/spesifikasi-backend-rute-nelayan-golang-gin.md).

## Deployment

Konfigurasi Railway ada di `railway.json`; deployment demo yang tercatat memakai upload CLI lokal, bukan auto-deploy GitHub. Verifikasi health langsung sebelum presentasi. [`render.yaml`](../../render.yaml) juga menyediakan alternatif Render Blueprint untuk Docker, region Singapura, branch `main`, dan build saat `backend/api/**` berubah. Berkas itu adalah konfigurasi alternatif, bukan bukti deployment aktif. Untuk menggunakannya, pilih `Malwildan/reefish` dan branch `main` di Render Blueprint, isi `SUPABASE_ANON_KEY` dengan anon/publishable key, lalu atur `ALLOWED_ORIGIN` sesuai origin web. Paket gratis dapat tidur setelah tidak aktif dan permintaan pertama dapat tertunda. Dockerfile juga mendukung Cloud Run, tetapi deployment Cloud Run tidak tercatat aktif. Jangan menaruh kunci service-role atau secret di environment yang dibundel ke klien.

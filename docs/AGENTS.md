# AGENTS.md — Sistem Rekomendasi Penangkapan Ikan Ramah Terumbu Karang

> Dokumen ini adalah **sumber kebenaran tunggal** untuk penyelarasan tim/agent **ML**, **Backend (BE)**, **Mobile (Flutter — nelayan)**, dan **Web (Next.js — admin)**.
> Setiap perubahan kontrak (skema DB, API, payload ML, layer peta, format ID grid) **wajib** diperbarui di sini terlebih dahulu sebelum diimplementasikan.

**Versi dokumen:** 0.8 — perubahan dari 0.7: pembagian tanggung jawab **Supabase vs Go** (bagian 1.1); bentuk batasan tunggal **`ZoneEntry`** + aturan evaluasi zona yang dihitung klien (`pkg/zonerule`); semua angka per grid dari satu snapshot `heatmap_cells`; grid zona tanpa data tetap terkirim; push notification perubahan zona (`registerDevice`) dan cakupan sinkron (`X-Heatmap-Version`).

Perubahan 0.7 dari 0.6: kontrak API nelayan lengkap di **bagian 12.B**; kapal diisi sekali saat onboarding (skema siap banyak kapal), snapshot spesifikasi kapal per trip; semua jenis trip (onboarding/manual/sailing) lewat satu `postTrip` idempoten; endpoint mode berlayar lama dihapus.

Perubahan 0.6 dari 0.5: mode berlayar otomatis mencatat titik tangkap saat kapal masuk radius titik rekomendasi (offline, di HP), `flag_source = rec_radius`.

Perubahan 0.5 dari 0.4: kontrak API admin lengkap (25 endpoint) dimasukkan ke **bagian 12.A**; `API_CONTRACT_ADMIN.md` tidak dipakai lagi. Skema DB dilengkapi tabel heatmap & dismiss flag.

Perubahan 0.4 dari 0.3: heatmap disatukan untuk admin & nelayan (satu endpoint, satu sumber `heatmap_cells`, sinkron via `heatmap_version`), ditambah endpoint refresh & delta heatmap.

Perubahan 0.3 dari 0.2: definisi zona = kumpulan grid **berbatasan** (tidak ada zona normal), auto-flag `restricted` oleh sistem, kontrak API admin dipisah ke `API_CONTRACT_ADMIN.md`.

Perubahan 0.2 dari 0.1:
- Admin dipindah ke **Next.js (web)**, Flutter khusus nelayan.
- Prinsip **indeks kelelahan karang** (bukan zero tolerance untuk semua area berkoral).
- Grid **500 m × 500 m**, area pilot **190 × 190 km** (380 × 380 = 144.400 grid).
- ID grid berbasis indeks **`a{y}b{x}`**, origin di kiri bawah pilot.
- Entitas **Zona** = kumpulan grid hasil multi-select; status dikelola di level zona.
- `allowed_gear` dihapus (di luar scope).

---

## 0. Ringkasan Masalah & Tujuan

**Masalah:** Terumbu karang terkikis karena penangkapan ikan berulang di area yang sama.

**Root cause:**
1. Nelayan tidak tahu kapan/di mana area karang aman untuk diambil ikannya.
2. Konsumsi BBM (solar) masih ditebak-tebak, sehingga nelayan memilih spot terdekat/yang sudah biasa → tekanan menumpuk di area yang sama.

**Solusi:** Sistem dengan 2 role:
- **Nelayan (aplikasi Flutter)** → mendapat rekomendasi titik tangkap, prediksi BBM, prediksi tangkapan, dan jam berlayar optimal, sambil menghindari area terbatas.
- **Admin / pihak konservasi (web Next.js)** → membaca heatmap per grid, mengelompokkan grid menjadi **zona**, dan menetapkan status zona: *terbatas* (boleh dengan kuota) atau *rehab penuh* (dilarang). Grid di luar zona = normal.

### Prinsip utama
1. **Tidak ada zero tolerance otomatis untuk area berkoral.** Area berkoral boleh dimanfaatkan selama **tingkat kelelahannya** masih rendah. Sistem mengukur **indeks kelelahan (fatigue index)** per grid: naik ketika grid ditekan penangkapan, turun (pulih) seiring waktu ketika grid diistirahatkan.
2. **Rekomendasi menyebarkan tekanan.** Grid yang lelah diberi penalti, grid yang pulih boleh direkomendasikan lagi → rotasi alami.
3. **Rekomendasi tidak pernah mengarah ke zona rehab penuh**, dan tidak mengarah ke zona terbatas yang kuotanya habis.
4. **Keputusan status zona tetap di tangan admin.** Sistem hanya memberi *saran* (batasi / siap dibuka kembali).

---

## 1. Arsitektur

```
┌──────────────────┐                     ┌──────────────┐     HTTP (internal)    ┌──────────────┐
│ Flutter (mobile) │ ──── HTTPS/JSON ──▶ │              │ ─────────────────────▶ │  ML Service  │
│ Nelayan          │ ◀────────────────── │   Go (Gin)   │ ◀───────────────────── │ (Python,     │
└──────────────────┘                     │   REST API   │                        │  FastAPI)    │
┌──────────────────┐                     │              │                        └──────┬───────┘
│ Next.js (web)    │ ──── HTTPS/JSON ──▶ │              │                               │ read-only
│ Admin konservasi │ ◀────────────────── │              │                               │
└──────────────────┘                     └──────┬───────┘                               │
                                                │ SQL (pgx)                             ▼
                                                ▼                         ┌───────────────────────────┐
                                  ┌─────────────────────────────────────▶ │ Supabase Postgres+PostGIS │
                                  │                                       └───────────────────────────┘
                           ┌──────┴───────┐
                           │ Worker (Go)  │ ── cuaca (Open-Meteo), agregasi grid, fatigue
                           └──────────────┘
```

| Komponen | Teknologi | Pengguna | Tanggung jawab |
|---|---|---|---|
| Mobile | Flutter (Android prioritas) | Nelayan | Auth, onboarding, peta, rekomendasi, mode berlayar, input trip, riwayat, buffer offline |
| Web | Next.js (App Router) | Admin | Login admin, heatmap per grid, multi-select grid, manajemen zona, statistik |
| BE | Go + Gin | — | Auth, RBAC, CRUD, agregasi grid & zona, fatigue, gateway ML, cache cuaca, validasi zona |
| DB | Supabase Postgres + **PostGIS** | — | Data utama + query spasial |
| ML | Python (FastAPI) | — | Prediksi BBM, prediksi tangkapan, ranking kandidat |
| Worker | Go (goroutine/cron) | — | Refresh cuaca, recompute statistik & fatigue, reset kuota |

**Keputusan penting:**
- **Auth custom di Go** (bcrypt + JWT), **tidak** memakai Supabase Auth, karena login no. telp di Supabase Auth membutuhkan OTP. Supabase hanya dipakai sebagai lapisan data (lihat 1.1).
- Flutter & Next.js **tidak pernah** memanggil ML atau Supabase langsung. Semua lewat BE.
- ML service **tidak** menulis ke DB. BE yang menyimpan hasil.
- Endpoint `/admin/*` hanya dipakai Next.js; Flutter **tidak** punya UI admin.

### 1.1 Pembagian tanggung jawab: Supabase vs Go Gin

**Prinsip:** Supabase = **lapisan data saja** (Postgres + PostGIS). Semua API, auth, aturan bisnis, penjadwalan, dan integrasi luar ada di **Go**. Flutter, Next.js, dan ML tidak pernah memakai SDK / API Supabase.

**Fitur Supabase**

| Fitur | Dipakai | Untuk apa |
|---|---|---|
| Postgres | ✅ | Semua tabel bagian 13 |
| PostGIS | ✅ | Geometri grid, zona, track. `ST_Union` (outline zona), `ST_Transform` (UTM ↔ WGS84), `ST_Intersects` (filter `bbox`), `ST_DWithin` (radius jangkau rekomendasi), `ST_Length` / `ST_MakeLine` (jarak track), `ST_SimplifyPreserveTopology` (track `simplified`), `ST_Touches` (cek grid zona bersebelahan) |
| Constraint & index | ✅ | Menjaga invarian walau ada bug di Go: satu zona aktif per grid (PK `zone_grids`), nama zona unik di antara zona aktif, satu kapal default per user, satu trip onboarding per user, idempotensi `(user_id, client_trip_id)`, satu refresh heatmap penuh sekaligus |
| Sequence | ✅ | `heatmap_version_seq` — nomor versi atomik & monoton |
| View | ✅ | `zone_aggregates`, `ml_training_trips` |
| Connection pooler (Supavisor) | ✅ | API Go lewat mode *transaction*; worker Go lewat koneksi *session*/langsung untuk job panjang |
| Role database | ✅ | `app_backend` (baca/tulis, dipakai Go) dan `ml_reader` (SELECT saja ke `ml_training_trips`, `grids`, `heatmap_cells`, `weather_cache`) |
| Backup / PITR | ✅ | Pemulihan data |
| Supabase Auth | ❌ | Auth custom di Go (login no. telp tanpa OTP) |
| Data API (PostgREST / GraphQL) | ❌ **dimatikan** | Mencegah akses langsung lewat anon key. Lapis kedua: **RLS aktif tanpa policy** di semua tabel, sehingga role `anon` / `authenticated` tidak bisa membaca apa pun |
| Realtime | ❌ | Klien tidak terhubung ke Supabase dan Flutter sering offline; sinkron memakai `heatmap_version` + push FCM |
| Edge Functions | ❌ | Semua logika di Go |
| Storage | ❌ (MVP) | Tidak ada upload file |
| pg_cron | ❌ | Penjadwalan di worker Go agar log, retry, dan monitoring di satu tempat |

**Tanggung jawab Go (API + worker)**

| Area | Ditangani Go |
|---|---|
| HTTP | Semua endpoint 12.A & 12.B: validasi, envelope, kode error, `ETag`/`304`, gzip, rate limit |
| Auth | Normalisasi no. telp, bcrypt, JWT, middleware RBAC, `X-Internal-Key` |
| Grid | `pkg/gridindex` (koordinat ↔ ID), encode sea-mask |
| Aturan zona | `pkg/zonerule` (evaluasi zona 12.A.2) — implementasi referensi untuk Flutter & Next.js |
| Zona | Konflik grid, `on_conflict`, optimistic locking, `zone_history`, arsip, kuota per periode, outline & bbox |
| Heatmap | Publish `grid_stats` → `heatmap_cells`, penomoran versi, delta `changes` |
| Worker | Fatigue, smoothing, auto-flag, saran reopen, reset kuota, cuaca, kirim push |
| Trip | Idempotensi, metrik turunan, alokasi kg, `zone_at_time`, snapshot kapal |
| Rekomendasi | Kandidat & pre-filter, panggil ML, fallback heuristik, cache & invalidasi |
| Integrasi luar | Open-Meteo (cuaca), FCM (push notification) |
| Sinkron | Middleware `X-Heatmap-Version` → cakupan sinkron |

**Pemetaan per endpoint**

| Endpoint | Logika di Go | Data & fitur Supabase |
|---|---|---|
| `register`, `login`, `me` | normalisasi telp, bcrypt, JWT, `next_step` | `users`, `boats`, `trips` (hitung) |
| `createBoat`, `updateBoat` | validasi, batas 1 kapal, hapus cache rekomendasi | `boats` + index `boats_one_default` |
| `postTrip` | validasi, `gridindex`, `zonerule` (`zone_at_time`), alokasi kg, metrik, rekomendasi sinkron, antre job | `trips`, `trip_points`, `fishing_points` dalam 1 transaksi; unique `client_trip_id`; `ST_MakeLine`/`ST_Length` |
| `getHistoryTrip`, `getTripDetail` | paginasi, ringkasan | `trips`, `fishing_points`, `trip_points` + `ST_SimplifyPreserveTopology` |
| `getRecommendation` | cache & invalidasi, kandidat, ML, fallback | `recommendations`, `heatmap_cells`, `zones`, `boats`, `weather_cache`; `ST_DWithin` |
| `getGridMeta`, `getSeaMask` | dibangun sekali saat start, disimpan di memori | `grids.is_sea` |
| `getZones`, `getHeatmap`, `getHeatmapVersion`, `getHeatmapChanges` | serialisasi, `ETag`, delta | `heatmap_cells`, `zones` (outline tersimpan), `zone_grids`, `zone_quota_usage`, `heatmap_versions` |
| `getWeatherInfo`, `getWeatherArea` | pilih sel terdekat, hitung `risk` | `weather_cache` |
| `previewZona`, `createZona`, `editZona`, `editGridZona`, `editStatusZona` | aturan bisnis, transaksi, history, publish, antre push | `zones`, `zone_grids`, `zone_history`, `heatmap_cells`, `heatmap_version_seq`, `push_outbox`; `ST_Union`, `ST_Touches` |
| `getGridDetail` | — | `heatmap_cells`, `grids`, `grid_daily_load` (tren) |
| `refreshHeatmap`, `automaticFlagToRestricted`, `dismissFlag` | job runner, logika flag | `heatmap_refresh_jobs`, `grid_stats`, `heatmap_cells`, `flag_dismissals` |
| `listFlags`, `zoneHistory`, `statsSummary` | agregasi | tabel & view terkait, `users.last_heatmap_version` |
| `registerDevice`, `unregisterDevice` | upsert token | `user_devices` |
| `getMobileConfig` | cache di memori | `app_config` |

---

## 2. Konvensi Global (WAJIB)

| Hal | Konvensi |
|---|---|
| Koordinat geografis | WGS84 / **EPSG:4326**. GeoJSON `[lng, lat]`; objek JSON biasa `{ "lat": ..., "lng": ... }` |
| Proyeksi grid | **UTM zona 49S (EPSG:32749)** — semua perhitungan grid dalam meter di proyeksi ini |
| Ukuran grid | **500 m × 500 m** |
| Area pilot | **190 km × 190 km** → **380 kolom × 380 baris = 144.400 grid** |
| ID grid | **`a{y}b{x}`**, contoh `a12b34` (lihat bagian 5.1). **Bukan koordinat** |
| Waktu | Disimpan **UTC** (`timestamptz`), dikirim ISO-8601. UI menampilkan **WIB (Asia/Jakarta)** |
| Jam rekomendasi | `HH:mm` WIB + `for_date` |
| BBM | Liter (`fuel_liters`). Istilah UI: **"Solar/BBM"** |
| Berat ikan | Kilogram (`catch_kg`) |
| Jarak | Kilometer (`*_distance_km`, mis. `distance_from_port_km`) |
| Angin | Kecepatan m/s; arah derajat 0–360 (arah **asal** angin) + label `U, TL, T, TG, S, BD, B, BL` |
| Skor/indeks | Selalu dinormalisasi **0–1** |
| JSON | `snake_case` |
| Error | `{ "error": { "code": "STRING_CODE", "message": "..." } }` |
| ID entitas | UUID v4 (kecuali grid) |
| Bahasa UI | Bahasa Indonesia |

---

## 3. Role & RBAC

| Role | Cara dibuat | Klien | Akses |
|---|---|---|---|
| `fisher` | Register publik (no. telp + password) | Flutter | Data milik sendiri, peta zona, heatmap agregat (sama dengan admin), rekomendasi |
| `admin` | **Seeder** saja | Next.js | Data agregat grid/zona, manajemen zona, statistik |

**Aturan BE:**
- JWT berisi `sub`, `role`, `exp`. Access token 7 hari (nelayan sering offline). Tanpa refresh token di MVP.
- Middleware `RequireRole("admin")` untuk `/admin/*`, `RequireRole("fisher")` untuk trip & rekomendasi.
- Login memakai endpoint yang sama; Flutter **menolak** login jika `role = admin` (tampilkan "Gunakan dashboard web"), Next.js **menolak** jika `role = fisher`.
- Nelayan tidak bisa melihat trip/lokasi nelayan lain secara individual.
- Next.js menyimpan JWT di **cookie httpOnly** (via route handler/middleware Next.js), bukan `localStorage`.

---

## 4. Daftar Fitur

### 4.1 Nelayan (Flutter)
1. **Register** — `name`, `phone`, `password`. Tanpa OTP/verifikasi. Phone dinormalisasi ke `+62…`. Password **bcrypt (cost 12)**.
2. **Login** — `phone` + `password` → JWT.
3. **Onboarding** (wajib sekali): kapal diisi **sekali** + 1 trip baseline (`postTrip`, 12.B.4) berisi koordinat berangkat, titik tangkap, BBM (liter), tangkapan (kg), jam berangkat & pulang.
4. **Rekomendasi** (setelah onboarding & setiap trip selesai) — 4 tipe: `fuel_saving`, `catch_max`, `balanced`, `habitual`.
5. **Dashboard peta** — zona, grid (zoom dekat), heatmap kondisi area, titik rekomendasi, posisi user, cuaca.
6. **Cuaca** — kondisi cuaca, arah angin, kecepatan angin, suhu (+ tinggi gelombang).
7. **Catat trip** — manual (pasca berlayar) atau **Mode Berlayar** (real-time, polling 2 menit).
8. **Riwayat trip** — list + detail.

### 4.2 Admin (Next.js)
1. Login (akun seed).
2. **Heatmap per grid** — metrik: kelelahan (fatigue), tekanan, CPUE.
3. **Multi-select grid → buat Zona** (nama + status + aturan).
4. **Kelola zona** — ubah status/aturan, tambah/kurangi grid, nonaktifkan zona.
5. **Detail zona** — data **agregat** semua grid di dalamnya.
6. **Detail grid** — statistik satu grid & zona tempat grid berada.
7. **Saran sistem** — grid/zona yang disarankan untuk dibatasi atau siap dibuka.
8. **Audit log** perubahan zona.
9. **Statistik ringkas** — total trip, zona paling lelah, pelanggaran.

---

## 5. Model Domain: Grid

### 5.1 Sistem ID grid

- Origin `(0,0)` = **ujung kiri bawah (barat daya)** area pilot, dalam meter UTM 49S: `origin_x`, `origin_y` (konfigurasi).
- **x → B** (kolom, barat → timur): `b1 … b380`
- **y → A** (baris, selatan → utara): `a1 … a380`
- **ID = `a{A}b{B}`** — contoh `a1b1` (paling kiri bawah), `a380b380` (paling kanan atas).
- Indeks **mulai dari 1**.

**Rumus (WAJIB sama di BE, Flutter, Next.js, ML):**

```
// koordinat → ID
(x_m, y_m) = project_to_utm49s(lng, lat)
b = floor((x_m - origin_x) / 500) + 1
a = floor((y_m - origin_y) / 500) + 1
valid jika 1 <= a <= 380 dan 1 <= b <= 380

// ID → titik tengah
x_center = origin_x + (b - 0.5) * 500
y_center = origin_y + (a - 0.5) * 500
(lng, lat) = unproject_from_utm49s(x_center, y_center)

// ID → batas sel (persegi di UTM)
x_min = origin_x + (b - 1) * 500 ; x_max = x_min + 500
y_min = origin_y + (a - 1) * 500 ; y_max = y_min + 500
```

Library proyeksi: Go `github.com/wroge/wgs84` atau PostGIS `ST_Transform`; Flutter `proj4dart`; Next.js `proj4`; Python `pyproj`.

> **Catatan:** area pilot 190 km sebaiknya berada di zona UTM 49 (108°–114° BT). Jika sebagian melewati 114° BT, tetap pakai EPSG:32749 untuk seluruh pilot agar grid konsisten; distorsinya kecil untuk skala ini.

**Tetangga grid:** `(a±1, b±1)` — dipakai untuk smoothing statistik dan pemilihan rectangle.

### 5.2 Data per grid

| Kelompok | Field | Sumber |
|---|---|---|
| **Identitas** (statis) | `id`, `a`, `b`, `geom`, `centroid`, `is_sea` | Seeder |
| **Habitat** | `has_coral`, `coral_cover_pct` (opsional), `coral_sensitivity` (0–1) | Seeder / admin |
| **Statistik** (worker) | `trip_count_7d`, `trip_count_30d`, `fishing_hours_30d`, `catch_kg_30d`, `cpue_30d`, `pressure_index`, `last_visited_at` | Agregasi trip |
| **Kelelahan** (worker) | `fatigue_index`, `fatigue_level`, `fatigue_updated_at`, `days_since_last_load` | Rumus 5.3 |
| **Keanggotaan zona** | `zone_id` (nullable; maksimal **1 zona aktif** per grid) | Admin |
| **Saran** | `suggestion` (`restrict \| reopen \| null`) | Worker |

Grid tanpa zona = **normal** secara default.

### 5.3 Indeks Kelelahan (Fatigue Index)

Tujuan: mengukur seberapa "capek" area dari tekanan penangkapan, dengan memperhitungkan pemulihan alami.

Dihitung **harian** per grid oleh worker:

```
load_d   = w_h * norm(fishing_hours_hari_ini) + w_c * norm(catch_kg_hari_ini) + w_v * norm(jumlah_kunjungan_hari_ini)
F_d      = clamp( F_{d-1} * exp(-λ * Δt) + α * load_d , 0, 1 )

α        = α_base * (0.5 + coral_sensitivity)   // grid berkoral lebih cepat lelah
λ        = ln(2) / half_life_days               // laju pemulihan
```

| Parameter | Default awal | Keterangan |
|---|---|---|
| `w_h, w_c, w_v` | 0.4, 0.4, 0.2 | bobot jam tangkap, kg, kunjungan |
| `α_base` | 0.15 | sensitivitas beban |
| `half_life_days` | 60 (berkoral), 21 (tidak berkoral) | waktu pemulihan setengah |
| `norm()` | dibagi persentil 95 dari seluruh grid | agar skala stabil |

> Semua parameter disimpan di tabel konfigurasi, **bukan hardcode**, dan harus divalidasi dengan pihak konservasi.

**Level kelelahan:**

| Level | Rentang | Warna | Arti |
|---|---|---|---|
| `healthy` | < 0.4 | hijau | Aman dimanfaatkan |
| `tired` | 0.4 – 0.7 | kuning | Kurangi tekanan |
| `critical` | ≥ 0.7 | merah | Perlu diistirahatkan |

**Saran otomatis (tidak mengubah status):**
- **Auto-flag `restricted`** — grid tanpa zona dengan `fatigue_index ≥ 0.7` ditandai sistem; flag hilang saat `fatigue_index < 0.5` atau grid masuk zona. Hanya penanda tampilan, tidak membatasi nelayan. Detail: `automaticFlagToRestricted` di bagian 12.A.8.
- `reopen` — grid di zona rehab dengan `fatigue_index < 0.2` selama ≥ 30 hari berturut-turut.

Zona rehab tidak mendapat beban baru → fatigue turun alami → muncul saran `reopen`. Inilah mekanisme **rotasi**, bukan larangan permanen.

### 5.4 Smoothing statistik
Grid 500 m membuat data per grid jarang (sparse). Untuk heatmap & ML, sediakan juga nilai **smoothed** (rata-rata berbobot dengan 8 tetangga) di field `*_smooth`. Heatmap admin menampilkan nilai mentah secara default, dengan toggle "haluskan".

---

## 6. Model Domain: Zona

Zona = **sekumpulan grid yang memiliki batasan penangkapan ikan**, dipilih admin dan dikelola sebagai satu unit kebijakan.
- Status zona hanya `restricted` atau `rehab`. **Tidak ada zona berstatus normal**; grid tanpa zona = normal.
- Mengubah status zona ke `normal` = **membubarkan zona** (diarsipkan, grid dilepas, hilang dari list, heatmap diperbarui).
- Kontrak API lengkap: **bagian 12.A**.

### 6.1 Field zona

| Field | Keterangan |
|---|---|
| `id` | UUID |
| `name` | Nama zona, wajib, unik (mis. "Karang Teluk Sendang Biru") |
| `status` | `restricted \| rehab` (normal = zona dibubarkan) |
| `max_catch_kg_per_period` | Hanya untuk `restricted` |
| `max_trips_per_period` | Hanya untuk `restricted` |
| `period` | `weekly \| monthly` |
| `open_schedule` | Jadwal buka (hari/jam), JSON, opsional |
| `effective_from`, `effective_until` | Masa berlaku status |
| `reason`, `note` | Alasan penetapan |
| `is_active` | Zona bisa dinonaktifkan tanpa dihapus |
| `created_by`, `created_at`, `updated_at` | Audit |

### 6.2 Aturan zona
- Satu grid **maksimal satu zona aktif**. Jika admin memilih grid yang sudah masuk zona lain, UI memberi peringatan dengan opsi **pindahkan ke zona baru** atau **lewati grid tersebut**.
- Grid daratan (`is_sea = false`) tidak bisa masuk zona.
- Grid dalam zona tidak harus bersebelahan (diperbolehkan), tetapi UI menampilkan peringatan jika terpisah jauh.
- Status grid untuk keperluan rekomendasi & peringatan = status zonanya.
- Zona `restricted` yang kuotanya habis diperlakukan seperti `rehab` **untuk rekomendasi** sampai periode berikutnya (status asli tidak berubah).
- Setiap perubahan (status, aturan, anggota grid) dicatat di audit log.

### 6.3 Status zona

| Status | Kode | Arti untuk nelayan | Boleh direkomendasikan? |
|---|---|---|---|
| Normal (tanpa zona) | — | Bebas menangkap | Ya (dengan penalti fatigue) |
| Terbatas | `restricted` | Boleh dengan kuota/jadwal | Ya, jika kuota tersisa & dalam jadwal |
| Rehab penuh | `rehab` | Dilarang total | **Tidak pernah** |

### 6.4 Data agregat zona (ditampilkan di admin)
Dihitung dari seluruh grid anggota (view/query):

| Metrik | Agregasi |
|---|---|
| `grid_count`, `area_km2` | count, `grid_count × 0.25` |
| `coral_grid_count`, `coral_pct` | count/persen grid `has_coral` |
| `fatigue_avg`, `fatigue_max` | rata-rata, maksimum |
| `fatigue_distribution` | jumlah grid per level (healthy/tired/critical) |
| `trip_count_30d` | jumlah trip unik yang menyentuh zona |
| `catch_kg_30d`, `fishing_hours_30d` | sum |
| `cpue_30d` | `catch_kg_30d / fishing_hours_30d` |
| `quota_used_kg`, `quota_used_trips`, `quota_remaining_*` | untuk `restricted` |
| `violation_count_30d` | trip yang masuk saat zona `rehab` |
| `suggestion_counts` | jumlah grid dengan saran restrict/reopen |

---

## 7. Fitur Peta

### 7.1 Strategi data peta (karena 144.400 grid)
- **Geometri grid TIDAK dikirim sebagai GeoJSON.** Klien membangun sel sendiri dari `GET /map/grid-meta` (origin, ukuran sel, jumlah baris/kolom, EPSG) dengan rumus 5.1.
- **Mask laut/darat** dikirim sekali sebagai bitset terkompresi (`GET /map/sea-mask`), di-cache dengan `version`.
- **Nilai layer dikirim sparse**: hanya grid yang punya nilai, format tuple + `columns`, semua metrik & kamus zona dalam satu payload (lihat bagian 12.A.4).
- Semua endpoint nilai menerima filter rentang indeks (`a_min,a_max,b_min,b_max`) **atau** `bbox` (BE mengonversi ke rentang indeks).
- Garis grid hanya digambar pada **zoom tinggi** (mis. zoom ≥ 13), karena di zoom jauh 500 m terlalu rapat.
- **Zona dikirim sebagai daftar grid ID per zona + outline gabungan** (outline dihitung BE dengan `ST_Union`, dikirim GeoJSON) agar ringan dirender.

### 7.2 Daftar layer

| # | Layer | Bentuk render | Nelayan (Flutter) | Admin (Next.js) | Endpoint |
|---|---|---|---|---|---|
| L0 | Basemap laut | Raster tile | ✅ | ✅ | OSM / ESRI Ocean |
| L1 | Garis grid 500 m | Garis (zoom ≥ 13) | ✅ | ✅ | `/map/grid-meta` (dibangun klien) |
| L2 | Zona | Fill + outline per zona | ✅ | ✅ | `/map/zones` |
| L3 | Heatmap kelelahan | Fill per grid | ✅ | ✅ | `/map/heatmap` (kolom `fatigue`) |
| L4 | Heatmap tekanan | Fill per grid | ✅ | ✅ | `/map/heatmap` (kolom `pressure`) |
| L5 | Heatmap CPUE | Fill per grid | ✅ | ✅ | `/map/heatmap` (kolom `cpue`) |
| L6 | Auto-flag sistem | Outline oranye putus-putus | ✅ | ✅ | `/map/heatmap` (kolom `auto_flag`) |
| L7 | Seleksi grid | Highlight biru | ❌ | ✅ | state lokal |
| L8 | Titik rekomendasi | Marker + garis dari dermaga | ✅ | ❌ | `/recommendations` (12.B.5) |
| L9 | Posisi & track berlayar | Marker + polyline | ✅ | ❌ | GPS lokal |
| L10 | Titik tangkap historis user | Marker kecil | ✅ | ❌ | `/trips/{id}` |
| L11 | Cuaca / panah angin | Ikon per sel sampel | ✅ | ✅ | `/weather/area` |

**Warna standar:**
- Grid ber-auto-flag: outline oranye putus-putus `#EF6C00`
- Zona terbatas: kuning `#F9A825` (opacity 0.35)
- Zona rehab penuh: merah `#C62828` (opacity 0.45) + arsiran
- Heatmap kontinu: gradasi hijau → kuning → merah (0 → 1); grid tanpa data: tidak diwarnai
- Seleksi admin: biru `#1565C0` (opacity 0.5)
- Zona `scheduled` (belum berlaku): outline abu `#757575` putus-putus + label tanggal mulai
- Warna zona ditentukan oleh `enforcement` (12.A.2), bukan langsung oleh `status`

> Heatmap disajikan **per grid (choropleth)**, bukan heatmap titik bebas — konsisten dengan unit zonasi dan tidak mengekspos lokasi individu nelayan.

> **Heatmap & batasan identik di kedua role.** Admin dan nelayan membaca satu sumber (`heatmap_cells`) lewat endpoint yang sama, dengan skala warna dan ambang yang sama. Sinkronisasi memakai `heatmap_version` + endpoint delta. Detail: bagian 12.A.4 & 12.A.5.

### 7.3 Skema penampilan: **per layer**
BE mengirim layer terpisah; klien yang menumpuk dan men-toggle. Alasan: admin perlu membandingkan heatmap dengan zona; frekuensi update tiap layer berbeda (grid-meta: statis, zona: jarang, heatmap: harian, cuaca: per jam) sehingga cache bisa per layer.

**Urutan z-index (bawah → atas):** L0 → L3/L4/L5 → L1 → L2 → L6 → L7 → L11 → L10 → L8 → L9

### 7.4 Library render
| Klien | Library | Catatan |
|---|---|---|
| Next.js | **MapLibre GL JS** + **deck.gl** (`PolygonLayer`/`SolidPolygonLayer` atau `GridCellLayer`) | deck.gl mampu render ratusan ribu sel via WebGL |
| Flutter | `flutter_map` | Render heatmap hanya untuk rentang indeks yang terlihat; gunakan `PolygonLayer` dengan culling, atau tile raster heatmap dari BE bila performa kurang |

### 7.5 Interaksi peta

**Nelayan (Flutter):**
- Pan / zoom / pinch, tombol "Lokasi saya", toggle layer.
- Tap area → bottom sheet: ID grid, nama & status zona, aturan (kuota tersisa, jadwal), kondisi area (sehat/lelah/kritis), cuaca.
- Tap marker rekomendasi → detail + tombol "Mulai Berlayar ke sini".
- Mode berlayar: peta mengikuti posisi; peringatan (getar + banner) saat masuk zona rehab / zona terbatas yang kuotanya habis.
- Input trip manual: tap peta untuk menaruh titik berangkat / titik tangkap, drag untuk koreksi.

**Admin (Next.js) — alur utama:**
1. **Lihat heatmap per grid** — pilih metrik (kelelahan/tekanan/CPUE) dan jendela waktu (7/30 hari). Hover grid → tooltip ID + nilai.
2. **Pilih grid** (multi-select):
   - Klik → toggle satu grid.
   - **Shift + drag** → pilih kotak (rentang `a`, `b`; mudah karena berbasis indeks).
   - **Ctrl/Cmd + klik** → hapus satu dari seleksi.
   - Grid daratan tidak bisa dipilih; grid yang sudah punya zona diberi tanda.
   - Panel menampilkan "N grid dipilih" + **preview agregat** (bagian 6.4) secara langsung.
3. **Buat zona** → form: nama zona, status, aturan (kuota/periode/jadwal jika `restricted`), masa berlaku, alasan → konfirmasi → simpan.
4. **Kelola zona** — dari daftar zona atau klik zona di peta: lihat agregat, ubah status/aturan, mode edit anggota (tambah/kurangi grid), nonaktifkan.
5. **Tindak lanjut saran** — klik saran `restrict`/`reopen` → langsung membuka form zona dengan grid terkait sudah terpilih.

---

## 8. Onboarding & Input Trip

### 8.1 Skema input (onboarding, manual, akhir mode berlayar)

```json
{
  "source": "onboarding | manual | sailing",
  "departure": { "lat": -8.123, "lng": 112.456 },
  "fishing_points": [
    { "lat": -8.30, "lng": 112.60, "started_at": "...", "ended_at": "..." }
  ],
  "fuel_liters": 25.5,
  "catch_kg": 40.0,
  "departed_at": "2026-10-15T21:00:00Z",
  "returned_at": "2026-10-16T05:00:00Z",
  "notes": "opsional"
}
```

> Kontrak final input trip: **`postTrip` (12.B.4)**. Contoh di atas adalah bentuk ringkasnya.

Profil kapal (diisi **sekali** saat onboarding lewat `createBoat`, disimpan di `boats`, spesifikasinya di-snapshot ke setiap trip dan dipakai ML):
```json
{ "engine_hp": 15, "boat_length_m": 7, "home_port": { "lat": -8.12, "lng": 112.45 } }
```

**Validasi BE:**
- `0 < fuel_liters ≤ 500`; `0 ≤ catch_kg ≤ 5000` (dapat dikonfigurasi).
- `returned_at > departed_at`, durasi ≤ 72 jam.
- `fishing_points` minimal 1, semua di dalam pilot & grid laut.
- `started_at`/`ended_at` titik tangkap opsional untuk `manual`/`onboarding`.

**Turunan yang dihitung BE saat simpan:**
- `grid_id` setiap titik tangkap (rumus 5.1).
- `distance_km` (dari track jika ada; jika tidak, garis lurus dermaga → titik-titik → dermaga).
- `duration_h`, `fishing_hours` per titik (jika ada waktu), `fuel_per_km`, `catch_per_liter`.
- Pembagian `catch_kg` ke grid: **proporsional terhadap durasi** di tiap titik; jika durasi tidak ada → **dibagi rata** (lihat Open Questions).
- `zone_violation = true` jika ada titik di zona `rehab` saat trip.
- Memicu recompute statistik grid terdampak.

### 8.2 Alur onboarding
1. `register` → `me` (`next_step = boat`).
2. `createBoat` — kapal, HP mesin, panjang, dermaga utama (sekali).
3. `postTrip` dengan `source = onboarding` — 1 trip baseline.
4. Response `postTrip` berisi `RecommendationSet` → tampilkan 4 tipe rekomendasi.
5. `users.onboarded = true` (`next_step = done`) → masuk dashboard.

---

## 9. Mode Berlayar (Flutter)

### 9.1 State machine

```
IDLE ──[Mulai Berlayar]──▶ SAILING ──[diam ≥ 2 mnt]──▶ CONFIRM_STOP (popup, timer 5 mnt)
                              ▲  │                           │
                              │  │◀─[user: "Tidak, masih jalan"]┤
                              │  │                           │
                              │  │            [user: "Ya" / timer habis]
                              │  │                           ▼
                              │  └──[masuk radius rekomendasi]──▶ FISHING (titik tangkap dibuat)
                              │                              │
                              └──[bergerak lagi / keluar radius]┘

SAILING / FISHING ──[Selesai Berlayar]──▶ POST_TRIP_FORM ──[submit]──▶ RECOMMENDATION
```

### 9.2 Aturan teknis
- **Polling GPS setiap 2 menit** (30 detik saat dekat target, lihat di bawah); titik disimpan lokal dan dikirim **sekaligus** lewat `postTrip` saat pelayaran selesai.
- **"Tidak bergerak"** = perpindahan dari titik sebelumnya **< 50 m** dan kecepatan GPS **< 0.5 m/s** (toleransi noise GPS). Ambang disimpan sebagai konfigurasi.
- Jika 1 interval tidak bergerak → **popup "Apakah Anda berhenti untuk menangkap ikan?"** dengan countdown **5 menit**:
  - "Ya" → titik tangkap (`flag_source = user_confirmed`).
  - "Tidak" → kembali SAILING.
  - Timer habis → titik tangkap otomatis (`flag_source = auto_timeout`).
- Selama FISHING polling tetap jalan; bergerak > 50 m → `ended_at` diisi, kembali SAILING.
- Saat aplikasi di background, popup diganti **notifikasi lokal** dengan aksi Ya/Tidak.

**Auto-flag di radius rekomendasi (offline, di HP):**
- **Titik target** = rekomendasi yang dipilih nelayan lewat "Mulai Berlayar ke sini". Jika tidak memilih, keempat titik rekomendasi terakhir dipakai sebagai target. Semua target disimpan lokal saat mode berlayar dimulai.
- Saat posisi GPS berada dalam **`sailing.rec_radius_m`** (default **500 m**) dari titik target → **langsung** masuk FISHING tanpa popup: titik tangkap dibuat dengan `flag_source = rec_radius` dan `recommendation_id` target tersebut.
- Selama berada di dalam radius, deteksi "diam 2 menit" + popup **tidak dijalankan** (agar tidak muncul popup ganda).
- **Keluar radius** = jarak > `rec_radius_m + 100 m` (histeresis agar tidak keluar-masuk karena noise GPS) → `ended_at` diisi, kembali SAILING.
- Banner/notifikasi lokal: "Anda tiba di titik rekomendasi — dicatat sebagai menangkap ikan", dengan tombol **"Bukan, saya hanya lewat"**. Jika ditekan, titik tangkap itu dibatalkan dan target tersebut tidak memicu auto-flag lagi di trip ini.
- **Polling adaptif:** saat jarak ke target terdekat ≤ 2 km, interval GPS diperpendek menjadi **30 detik**. Dengan interval 2 menit, kapal yang melaju bisa melewati radius 500 m tanpa satu pun titik GPS di dalamnya. Interval kembali 2 menit setelah jarak > 2 km.
- Semua perhitungan jarak dilakukan di HP (haversine), tidak membutuhkan sinyal.
- Target yang gridnya kini ber-`enforcement = closed` (12.A.2) atau rekomendasinya ditandai tidak berlaku (12.B.5) **tidak** memicu auto-flag. Yang muncul adalah peringatan "Titik rekomendasi ini sekarang zona terlarang".

### 9.3 Kebutuhan teknis Flutter
- **Foreground service** Android ("Mode Berlayar aktif") agar GPS jalan saat layar mati; izin lokasi background.
- **Offline-first:** track & titik tangkap disimpan di SQLite/Hive lokal. Trip selesai masuk antrean *outbox* dan dikirim lewat `postTrip` begitu ada sinyal. BE idempoten berdasarkan `client_trip_id` (12.B.4).
- **Deteksi berhenti dihitung di HP** (agar jalan offline).
- **Peringatan zona dihitung di HP**: cache peta `grid_id → status` dari `/map/zones`, hitung ID grid dari GPS (rumus 5.1) → lookup O(1).
- **Rekomendasi terakhir di-cache lokal** (titik, `recommendation_id`, tipe) supaya auto-flag radius jalan tanpa sinyal.

### 9.4 Akhir pelayaran
"Selesai Berlayar" → form 8.1 terisi otomatis dari tracking. User **hanya wajib** mengisi `fuel_liters` dan `catch_kg` (boleh koreksi lainnya) → `postTrip` (`source = sailing`) → rekomendasi baru.

---

## 10. Rekomendasi

### 10.1 Alur
1. Rekomendasi dibuat otomatis di `postTrip`, atau lewat `getRecommendation` (12.B.5) bila cache kosong / kedaluwarsa.
2. BE menyusun kandidat:
   - Grid laut dalam radius jangkau dari `home_port` kapal default (default ≤ 40 km, dapat dikonfigurasi).
   - **Kecualikan** zona `rehab` dan zona `restricted` dengan kuota habis / di luar jadwal.
   - **Pre-filter** (karena radius 40 km ≈ ribuan grid 500 m): ambil top **300** kandidat berdasarkan skor heuristik (CPUE smoothed tinggi, fatigue rendah, jarak) + seluruh grid historis user (untuk `habitual`).
3. BE mengirim kandidat + konteks user + cuaca ke ML `POST /ml/v1/recommend`.
4. ML mengembalikan prediksi & skor per kandidat untuk 4 tipe.
5. BE **validasi ulang** (safety net zona), terapkan penalti anti-penumpukan, simpan, kirim ke Flutter.

### 10.2 Output per rekomendasi (kontrak Flutter)

```json
{
  "id": "uuid",
  "type": "fuel_saving | catch_max | balanced | habitual",
  "grid_id": "a142b217",
  "point": { "lat": -8.31, "lng": 112.62 },
  "zone": { "id": "uuid|null", "name": "string|null", "status": "normal | restricted" },
  "zone_rules": { "quota_remaining_kg": 120, "open_schedule": null },
  "area_condition": "healthy | tired",
  "predicted_fuel_liters": 18.2,
  "fuel_efficiency_pct": 28.6,
  "predicted_catch_kg": 35.0,
  "predicted_catch_range_kg": [25.0, 45.0],
  "departure_time": "04:30",
  "return_time": "11:00",
  "for_date": "2026-10-17",
  "distance_km": 14.3,
  "weather_summary": { "wind_speed_ms": 4.2, "wind_dir_deg": 120, "wave_height_m": 0.8, "temp_c": 28, "risk": "low" },
  "confidence": 0.62,
  "reason": "Jarak dekat, angin mendukung saat berangkat, kondisi area sehat"
}
```

Rekomendasi **tidak pernah** menunjuk grid dengan `fatigue_level = critical`, kecuali sebagai `habitual` yang langsung diganti (lihat 10.4).

### 10.3 Definisi metrik
- **`fuel_efficiency_pct`** = `(baseline_fuel − predicted_fuel) / baseline_fuel × 100`, dengan `baseline_fuel` = rata-rata BBM riwayat nelayan (minimal trip onboarding). Boleh negatif (lebih boros, wajar untuk `catch_max`).
- **`predicted_catch_kg`** + rentang interval prediksi.
- **`confidence`** 0–1, rendah saat data user/grid sedikit.

### 10.4 Skor tiap tipe

Untuk kandidat `i` (semua 0–1):
- `F_i` = skor hemat BBM (`1 − fuel_norm`)
- `C_i` = skor tangkapan (`catch_norm`)
- `K_i` = **penalti kelelahan** = `fatigue_index` (dikalikan 2 jika `tired`)
- `P_i` = penalti penumpukan (jumlah rekomendasi ke grid yang sama hari itu)
- `W_i` = penalti risiko cuaca

| Tipe | Skor |
|---|---|
| `fuel_saving` | `0.6F + 0.2C − 0.15K − 0.05P − W` |
| `catch_max` | `0.2F + 0.6C − 0.15K − 0.05P − W` |
| `balanced` | `0.4F + 0.4C − 0.15K − 0.05P − W` |
| `habitual` | Grid yang paling sering dikunjungi user. Jika grid itu kini zona rehab / kuota habis / `critical` → diganti grid terdekat yang diizinkan, dan `reason` menjelaskan penggantinya |

> Bobot adalah **default awal**, disimpan di konfigurasi ML.

**Jam berangkat/pulang:** ML memilih jendela waktu dengan risiko cuaca terendah (forecast 48 jam), memperhitungkan waktu tempuh + durasi tangkap yang diprediksi.

---

## 11. Kontrak ML

### 11.1 Endpoint (internal, hanya dipanggil BE)

`POST /ml/v1/recommend`
```json
{
  "user": {
    "user_id": "uuid",
    "boat": { "engine_hp": 15, "boat_length_m": 7 },
    "home_port": { "lat": -8.12, "lng": 112.45 },
    "history_summary": {
      "trip_count": 5,
      "avg_fuel_liters": 25.5,
      "avg_catch_kg": 40,
      "avg_fuel_per_km": 0.9,
      "top_grids": [{ "grid_id": "a142b217", "visits": 3 }]
    }
  },
  "candidates": [
    {
      "grid_id": "a142b217",
      "centroid": { "lat": -8.31, "lng": 112.62 },
      "distance_km": 14.3,
      "zone_status": "normal",
      "fatigue_index": 0.22,
      "pressure_index": 0.2,
      "cpue_30d": 4.1,
      "cpue_30d_smooth": 3.8,
      "has_coral": true,
      "weather_forecast": [ { "time": "...", "wind_speed_ms": 4.2, "wind_dir_deg": 120, "wave_height_m": 0.8, "temp_c": 28 } ]
    }
  ],
  "date": "2026-10-17",
  "top_k": 1
}
```

Response:
```json
{
  "model_version": "rec-0.2.0",
  "results": {
    "fuel_saving": [ { "grid_id": "...", "predicted_fuel_liters": 18.2, "predicted_catch_kg": 35, "predicted_catch_range_kg": [25,45], "departure_time": "04:30", "return_time": "11:00", "score": 0.81, "confidence": 0.6, "reason_codes": ["NEAR", "TAILWIND", "HEALTHY_AREA"] } ],
    "catch_max": [],
    "balanced": [],
    "habitual": []
  }
}
```

`GET /ml/v1/health` → `{ "status": "ok", "model_version": "..." }`

### 11.2 Model
| Model | Target | Fitur utama | Cold start |
|---|---|---|---|
| Prediksi BBM | `fuel_liters` | jarak, HP mesin, panjang kapal, angin relatif terhadap arah tempuh, gelombang, durasi | `distance × fuel_per_km_user × faktor_cuaca` |
| Prediksi tangkapan | `catch_kg` | CPUE smoothed grid, durasi tangkap, bulan/musim, suhu, jam, fatigue | CPUE grid × durasi; fallback rata-rata user |
| Ranking | skor per tipe | output 2 model + penalti | Rumus 10.4 |

- Mulai heuristik → Gradient Boosting (LightGBM/XGBoost) saat data ≥ ~200 trip.
- `model_version` disimpan di setiap rekomendasi.
- Fatigue **dihitung BE/worker**, bukan ML (deterministik & dapat diaudit). ML hanya memakainya sebagai fitur/penalti.
- Data training dari view `ml_training_trips` (tanpa data pribadi).

### 11.3 Aturan ML agent
- **DILARANG** mengembalikan grid di luar `candidates`.
- Wajib mengembalikan 4 tipe; jika tidak ada kandidat valid → array kosong + `reason_codes: ["NO_VALID_CANDIDATE"]`.
- Timeout ≤ 3 detik; BE punya fallback heuristik.

---

## 12. API Backend (Go Gin)

Base: `/api/v1`. Semua endpoint kecuali `register`, `login`, dan `getMobileConfig` membutuhkan `Authorization: Bearer <jwt>`.

Kontrak lengkap dibagi dua:
- **12.A Admin (Next.js)** — termasuk endpoint **SHARED** peta & cuaca yang juga dipakai Flutter.
- **12.B Nelayan (Flutter)** — auth, kapal, trip, rekomendasi, cuaca titik.

Konvensi, envelope, paginasi, dan kode error umum di **12.A.1** berlaku untuk keduanya. Endpoint lama `/onboarding`, `/trips/sailing/start`, `/trips/{id}/points:batch`, `/trips/{id}/fishing-points`, `/trips/{id}/finish`, `/recommendations/generate`, `/recommendations/latest`, `PUT /me/boat`, dan `/map/grids/{grid_id}` **dihapus** dan digantikan kontrak 12.B.

### 12.A Kontrak API Admin (lengkap)

Kontrak ini mengikat **BE (Go Gin)** dan **Web (Next.js)**. Endpoint bertanda **SHARED** juga mengikat **Mobile (Flutter)**, dengan response yang sama persis untuk kedua role.

#### 12.A.0 Definisi & aturan dasar

- **Zona** = sekumpulan grid yang **memiliki batasan penangkapan ikan**. Status hanya `restricted` (boleh dengan kuota) atau `rehab` (dilarang total).
- **Tidak ada zona berstatus `normal`.** Grid yang tidak berada di zona aktif = normal.
- Mengubah status zona ke `normal` = **membubarkan zona**: zona diarsipkan (tidak dihapus), grid dilepas, zona hilang dari list, heatmap diperbarui.
- Satu grid maksimal berada di **satu zona aktif**.
- **Auto-flag** = penanda sistem untuk grid yang melewati kapasitas (`fatigue_index`). Tidak membuat zona dan tidak membatasi nelayan; hanya mengubah tampilan grid.
- **`heatmap_version`** = nomor versi global (monoton naik). Setiap perubahan yang memengaruhi tampilan peta menaikkannya.
- **Satu snapshot untuk semua angka per grid.** Worker menghitung di `grid_stats` (tabel kerja), lalu **mem-publish** ke `heatmap_cells` bersama kenaikan versi dalam satu transaksi. Semua endpoint yang menampilkan angka per grid atau agregat zona — `getHeatmap`, `getGridDetail`, `previewZona`, `readDetailZona`, `readListZona` — membaca **`heatmap_cells`** dan menyertakan `heatmap_version`, sehingga admin dan nelayan melihat angka yang sama untuk versi yang sama.
- **Satu bentuk batasan.** Zona selalu dikirim sebagai **`ZoneEntry`** (12.A.2) di semua endpoint.
- **Aturan waktu dihitung klien.** Apakah zona sedang berlaku dan sedang buka ditentukan dari data `ZoneEntry` + jam perangkat dengan aturan yang sama di Go, Flutter, dan Next.js (12.A.2). Server tidak mengirim nilai turunan waktu seperti `open_now`, karena nilai itu basi tanpa menaikkan versi.

#### 12.A.1 Konvensi

| Hal | Aturan |
|---|---|
| Base URL | `/api/v1` |
| Auth admin | `Authorization: Bearer <jwt>`, `role = admin`. Next.js menyimpan JWT di cookie httpOnly dan meneruskannya dari server |
| Auth SHARED | JWT `admin` atau `fisher` |
| Auth internal | Header `X-Internal-Key: <secret>`; hanya worker/cron, tidak pernah dari browser |
| Content-Type | `application/json`; response besar di-gzip |
| Waktu | ISO-8601 UTC; jam di `open_schedule` dalam WIB |
| ID grid | `a{y}b{x}` (bagian 5.1) |
| Sukses | `{ "data": ..., "meta": ... }` (`meta` hanya pada list) |
| Paginasi | Query `page` (mulai 1), `limit` (default 20, maks 100) → `meta: { page, limit, total }` |
| Error | `{ "error": { "code": "STRING", "message": "...", "details": {} } }` |
| Optimistic locking | Endpoint ubah zona wajib mengirim `version`; tidak cocok → `409 VERSION_CONFLICT` |
| `X-Heatmap-Version` | Header request dari **Flutter (wajib)** di setiap panggilan: versi heatmap yang dipegang HP. Next.js tidak mengirim. Dipakai untuk cakupan sinkron (12.B.10) |
| Versi data | Setiap response yang memuat angka per grid atau data zona menyertakan `heatmap_version` |

**Kode error**

| HTTP | `code` | Kapan |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Body/query tidak valid; `details.fields` = `{ field: pesan }` |
| 401 | `UNAUTHORIZED` | Token tidak ada / kedaluwarsa |
| 401 | `INVALID_CREDENTIALS` | No. telp atau password salah |
| 403 | `FORBIDDEN` | Role tidak sesuai / internal key salah |
| 404 | `ZONE_NOT_FOUND`, `GRID_NOT_FOUND`, `JOB_NOT_FOUND` | Data tidak ada |
| 409 | `ZONE_NAME_TAKEN` | Nama sudah dipakai zona aktif lain |
| 409 | `GRID_CONFLICT` | Grid sudah di zona aktif lain (`details.conflicts`) |
| 409 | `VERSION_CONFLICT` | `version` tidak cocok (`details.current_version`) |
| 409 | `ZONE_ARCHIVED` | Mengubah zona yang sudah dibubarkan |
| 409 | `REFRESH_IN_PROGRESS` | Refresh penuh heatmap masih berjalan |
| 410 | `FULL_RELOAD_REQUIRED` | `since` terlalu lama untuk delta heatmap |
| 422 | `GRID_INVALID` | Grid di luar pilot / grid daratan (`details.grid_ids`) |
| 422 | `RULES_REQUIRED` | Status `restricted` tanpa aturan kuota |
| 422 | `ZONE_EMPTY` | Operasi membuat zona tanpa grid |
| 422 | `SAME_STATUS` | Status baru sama dengan status sekarang |
| 429 | `TOO_MANY_ATTEMPTS` | Rate limit login |
| 500 | `INTERNAL_ERROR` | — |

#### 12.A.2 Objek bersama

**`ZoneRules`** — wajib untuk `restricted`, disimpan tapi tidak berlaku untuk `rehab`.
```json
{
  "max_catch_kg_per_period": 500,
  "max_trips_per_period": 40,
  "period": "weekly",
  "open_schedule": { "days": [1, 3, 5], "hours": ["05:00", "12:00"] }
}
```
- Minimal satu dari `max_catch_kg_per_period` / `max_trips_per_period` diisi.
- `period`: `weekly` (Senin 00:00 WIB) | `monthly` (tanggal 1 00:00 WIB).
- `open_schedule` opsional; `days` 1=Senin … 7=Minggu.

**`ZoneQuota`**
```json
{ "period_start": "2026-10-12", "used_kg": 210.0, "remaining_kg": 290.0, "used_trips": 9, "remaining_trips": 31, "exhausted": false }
```

**`ZoneAggregate`** — dihitung dari seluruh grid anggota, dibaca dari **`heatmap_cells`** (snapshot yang sama dengan heatmap).
```json
{
  "grid_count": 24,
  "area_km2": 6.0,
  "coral_grid_count": 18,
  "coral_pct": 75.0,
  "fatigue_avg": 0.58,
  "fatigue_max": 0.86,
  "fatigue_distribution": { "healthy": 6, "tired": 12, "critical": 6 },
  "flagged_grid_count": 0,
  "trip_count_30d": 41,
  "catch_kg_30d": 1320.5,
  "fishing_hours_30d": 310.0,
  "cpue_30d": 4.26,
  "violation_count_30d": 0,
  "quota": { "...": "ZoneQuota, null untuk rehab & preview" }
}
```

**`ZoneSummary`** — item list zona.
```json
{
  "id": "8f2c…",
  "name": "Karang Teluk Sendang Biru",
  "status": "restricted",
  "grid_count": 24,
  "area_km2": 6.0,
  "fatigue_avg": 0.58,
  "fatigue_max": 0.86,
  "quota_remaining_kg": 290.0,
  "quota_exhausted": false,
  "effective_until": null,
  "bbox": [112.55, -8.45, 112.62, -8.40],
  "is_active": true,
  "updated_at": "2026-10-16T00:00:00Z"
}
```

**`ZoneDetail`**
```json
{
  "id": "8f2c…",
  "name": "Karang Teluk Sendang Biru",
  "status": "restricted",
  "rules": { "...": "ZoneRules" },
  "reason": "Fatigue kritis di 6 grid berkoral",
  "note": null,
  "effective_from": "2026-10-17T00:00:00Z",
  "effective_until": null,
  "grid_ids": ["a12b34", "a12b35"],
  "outline": { "type": "MultiPolygon", "coordinates": [] },
  "bbox": [112.55, -8.45, 112.62, -8.40],
  "aggregate": { "...": "ZoneAggregate" },
  "grids": [
    { "grid_id": "a12b34", "has_coral": true, "fatigue_index": 0.86, "fatigue_level": "critical", "catch_kg_30d": 120.0, "trip_count_30d": 7 }
  ],
  "recent_history": [ { "...": "ZoneHistoryItem, maks 5" } ],
  "entry": { "...": "ZoneEntry — bentuk yang sama dengan yang diterima nelayan" },
  "sync": { "active_fishers_7d": 57, "known_by": 49, "known_by_pct": 86.0 },
  "is_active": true,
  "archived_at": null,
  "version": 1,
  "heatmap_version": 1043,
  "created_by": { "id": "…", "name": "Admin" },
  "created_at": "2026-10-16T00:00:00Z",
  "updated_at": "2026-10-16T00:00:00Z"
}
```
- `outline` = `ST_Union` geometri grid anggota, GeoJSON EPSG:4326 (disimpan di `zones.outline`).
- `grids` diurutkan `-fatigue_index`.
- `entry` = `ZoneEntry` persis seperti yang dikirim ke Flutter, agar admin bisa memastikan batasan yang tampil di HP.
- `sync.known_by` = nelayan aktif 7 hari terakhir yang `last_heatmap_version ≥ changed_in_heatmap_version` zona ini (12.B.10).

**`ZoneHistoryItem`**
```json
{
  "id": 1201,
  "action": "update_status",
  "before": { "status": "rehab" },
  "after": { "status": "restricted", "rules": { "...": "..." } },
  "reason": "…",
  "changed_by": { "id": "…", "name": "Admin" },
  "changed_at": "2026-10-16T00:00:00Z"
}
```
`action`: `create` | `update_meta` | `update_rules` | `add_grids` | `remove_grids` | `update_status` | `archive`.

**`HeatmapCell`** — tuple, urutan kolom tetap:
`["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"]`
- `zone_id = null` → grid normal; `auto_flag` = `"restricted"` | `null`.

**Aturan sel yang dikirim heatmap:** sebuah sel dikirim jika **punya data** (`has_data`) **atau** berada di zona aktif **atau** ber-auto-flag. Grid rehab yang belum pernah didatangi nelayan tetap terkirim dengan metrik `null`, sehingga batasannya tetap tergambar di kedua role.

**`ZoneEntry`** — **satu-satunya** bentuk batasan zona. Dipakai sama persis di `getZones`, kamus `zones` pada `getHeatmap`, `zones_upserted` pada `getHeatmapChanges`, `getGridDetail`, dan detail rekomendasi.
```json
{
  "id": "8f2c…",
  "name": "Karang Teluk Sendang Biru",
  "status": "restricted",
  "rules": { "...": "ZoneRules (null untuk rehab)" },
  "effective_from": "2026-10-17T00:00:00Z",
  "effective_until": null,
  "quota": {
    "period_start": "2026-10-12T00:00:00+07:00",
    "period_end": "2026-10-19T00:00:00+07:00",
    "remaining_kg": 290.0,
    "remaining_trips": null,
    "exhausted": false
  },
  "grid_ids": ["a12b34", "a12b35"],
  "bbox": [112.55, -8.45, 112.62, -8.40],
  "outline": { "type": "MultiPolygon", "coordinates": [] },
  "zone_version": 3,
  "changed_in_heatmap_version": 1043,
  "updated_at": "2026-10-16T00:00:00Z"
}
```
- `quota = null` untuk zona `rehab`.
- `outline` hanya ada jika request meminta (`include_outline` / `include_zone_outline`); outline disimpan di `zones.outline`, tidak dihitung per request.
- `changed_in_heatmap_version` = versi saat zona terakhir berubah; dipakai untuk cakupan sinkron per zona.
- **Tidak ada `open_now`** — dihitung klien dengan aturan di bawah.

**Aturan evaluasi zona** — WAJIB identik di Go (`pkg/zonerule`), Flutter, dan Next.js. BE menyediakan test vector seperti `pkg/gridindex`.
```
// semua waktu dikonversi ke WIB (Asia/Jakarta); now = jam perangkat / server
isEffective(z, now) = (z.effective_from  == null || now >= z.effective_from)
                   && (z.effective_until == null || now <  z.effective_until)

isOpen(z, now)      = z.rules == null || z.rules.open_schedule == null
                   || (isoWeekday(now) ∈ open_schedule.days
                       && open_schedule.hours[0] <= HH:mm(now) < open_schedule.hours[1])

quotaExhausted(z, now) = z.quota != null && z.quota.exhausted && now < z.quota.period_end
                         // setelah period_end kuota dianggap reset walau data belum disinkron

enforcement(z, now):
  if now <  z.effective_from                    → "scheduled"
  if z.effective_until != null && now >= until  → "expired"
  if z.status == "rehab"                        → "closed"
  if quotaExhausted(z, now) || !isOpen(z, now)  → "closed"
  else                                          → "limited"
```

| `enforcement` | Tampilan peta (kedua role) | Peringatan mode berlayar | Rekomendasi |
|---|---|---|---|
| `closed` | merah `#C62828` + arsiran | getar + banner | tidak pernah |
| `limited` | kuning `#F9A825` | banner info kuota & jadwal | boleh |
| `scheduled` | outline abu putus-putus + label "Berlaku mulai {tanggal}" | tidak | dihindari jika mulai berlaku sebelum `return_time` |
| `expired` | tidak digambar (admin: abu di daftar zona) | tidak | boleh |

Klien menghitung ulang `enforcement` **setiap 1 menit** dari data lokal, tanpa request. Rekomendasi di BE memakai `pkg/zonerule` yang sama untuk rentang `departure_time`–`return_time`.

---

#### 12.A.3 Auth

##### `login` — `POST /auth/login`
Publik, dipakai admin & nelayan. Rate limit: 5 percobaan / 15 menit per no. telp.

Request
```json
{ "phone": "081234567890", "password": "rahasia123" }
```
Response `200`
```json
{
  "data": {
    "token": "eyJ…",
    "expires_at": "2026-10-23T00:00:00Z",
    "user": { "id": "…", "name": "Admin Konservasi", "phone": "+6281234567890", "role": "admin", "onboarded": true }
  }
}
```
Error: `400`, `401 INVALID_CREDENTIALS`, `429 TOO_MANY_ATTEMPTS`.
Next.js **menolak** (tidak menyimpan cookie) jika `role ≠ admin`.

##### `me` — `GET /me`
Response `200`: `{ "data": { "id", "name", "phone", "role", "onboarded" } }`. Error: `401`. Untuk `role = fisher`, response ditambah `next_step`, `boat`, dan `stats` (12.B.3).

---

#### 12.A.4 Peta (SHARED)

##### `getGridMeta` — `GET /map/grid-meta`
Statis; `ETag: "<version>"`, dukung `304`.
```json
{
  "data": {
    "epsg": 32749, "origin_x": 650000.0, "origin_y": 9000000.0,
    "cell_size_m": 500, "rows": 380, "cols": 380,
    "id_format": "a{row}b{col}", "version": 1
  }
}
```
Nilai origin hanya contoh (Open Question 1).

##### `getSeaMask` — `GET /map/sea-mask`
```json
{ "data": { "encoding": "bitset-base64", "order": "a_then_b", "length": 144400, "bits": "…", "version": 1 } }
```
Bit ke-`(a-1)*380 + (b-1)` = 1 jika grid laut. `ETag` + `304`.

##### `getZones` — `GET /map/zones`
Zona aktif lengkap (`ZoneEntry`). Dipakai untuk **muat awal** dan setelah `410 FULL_RELOAD_REQUIRED`; pembaruan berikutnya cukup lewat `zones_upserted` / `zones_removed` di `getHeatmapChanges`.

| Query | Default | Keterangan |
|---|---|---|
| `bbox` | seluruh pilot | zona yang beririsan |
| `include_outline` | true | false = tanpa geometri |

Header: `ETag: "<heatmap_version>"`; `If-None-Match` → `304`.

```json
{
  "data": {
    "heatmap_version": 1044,
    "zones": [ { "...": "ZoneEntry" } ]
  }
}
```

##### `getHeatmap` — `GET /map/heatmap`
Satu sumber (`heatmap_cells`) untuk admin & nelayan. Geometri tidak dikirim; klien membangun sel dari `grid-meta`.

| Query | Default | Keterangan |
|---|---|---|
| `window` | `30d` | `7d` \| `30d`, untuk `pressure` & `cpue` |
| `smooth` | false | nilai smoothing 8 tetangga |
| `bbox` | seluruh pilot | `minLng,minLat,maxLng,maxLat` |
| `a_min,a_max,b_min,b_max` | — | alternatif `bbox` |
| `include_empty` | false | true = sertakan juga grid laut tanpa data, tanpa zona, dan tanpa flag (biasanya tidak perlu) |
| `include_zone_outline` | false | true = `ZoneEntry` di kamus `zones` membawa `outline` |

Header: `ETag: "<heatmap_version>"`; request `If-None-Match` → `304`.

Response `200`
```json
{
  "data": {
    "heatmap_version": 1044,
    "generated_at": "2026-10-16T17:10:04Z",
    "window": "30d",
    "smooth": false,
    "scale": {
      "fatigue":  { "min": 0, "max": 1, "thresholds": { "tired": 0.4, "critical": 0.7 } },
      "pressure": { "min": 0, "max": 1 },
      "cpue":     { "min": 0, "max": 9.8, "unit": "kg/jam" }
    },
    "columns": ["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"],
    "cells": [
      ["a12b34",  0.86, "critical", 0.71, 4.2, true,  "8f2c…", null],
      ["a40b120", 0.74, "critical", 0.66, 3.9, true,  null,    "restricted"],
      ["a13b34",  null, null,       null, null, true, "8f2c…", null]
    ],
    "zones": { "8f2c…": { "...": "ZoneEntry" } }
  }
}
```
- Semua metrik dalam satu payload → ganti metrik tanpa request ulang.
- Sel ketiga contoh: grid zona yang belum punya data (metrik `null`) tetap dikirim.
- `cpue.max` = persentil 95.

##### `getHeatmapVersion` — `GET /map/heatmap/version`
```json
{ "data": { "heatmap_version": 1046, "updated_at": "2026-10-16T01:02:00Z" } }
```

##### `getHeatmapChanges` — `GET /map/heatmap/changes`
| Query | Wajib | Keterangan |
|---|---|---|
| `since` | ✅ | `heatmap_version` yang dimiliki klien |
| `window`, `smooth`, `bbox`, `include_zone_outline` | ❌ | sama dengan `getHeatmap` |

```json
{
  "data": {
    "from_version": 1044,
    "to_version": 1046,
    "columns": ["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"],
    "upserts": [ ["a12b34", 0.86, "critical", 0.71, 4.2, true, null, null] ],
    "zones_upserted": { "51ab…": { "...": "ZoneEntry" } },
    "zones_removed": ["8f2c…"],
    "scale": { "...": "sama dengan getHeatmap" }
  }
}
```
- `since` = versi terkini → `upserts` kosong.
- `zones_upserted` memuat `ZoneEntry` **lengkap** (bukan selisih field) untuk setiap zona yang berubah, termasuk perubahan kuota.
- Sel yang keluar dari aturan kirim (mis. grid dilepas dari zona dan tidak punya data) dikirim sebagai upsert dengan `zone_id = null`, agar klien menghapus status lamanya.
- `410 FULL_RELOAD_REQUIRED` jika `since` lebih lama dari `heatmap.changes_max_versions` (50) versi atau `heatmap.changes_max_age_days` (7) hari.

##### `getWeatherArea` — `GET /weather/area`
| Query | Default | Keterangan |
|---|---|---|
| `bbox` | seluruh pilot | — |
| `hours` | 0 | jam ke depan dari sekarang (0–48) |

```json
{
  "data": {
    "forecast_time": "2026-10-16T00:00:00Z",
    "points": [
      { "cell_key": "c03_07", "lat": -8.40, "lng": 112.60, "wind_speed_ms": 4.2, "wind_dir_deg": 120, "wind_dir_label": "TG", "wave_height_m": 0.8, "temp_c": 28.1, "weather_code": 2, "risk": "low" }
    ]
  }
}
```

**Perilaku klien heatmap (wajib sama di Next.js & Flutter)**

| Momen | Aksi |
|---|---|
| Cache kosong | `getHeatmap` penuh, simpan beserta `heatmap_version` |
| Next.js, halaman peta terbuka | tiap 60 detik `getHeatmapVersion` → jika beda, `getHeatmapChanges` |
| Next.js, setelah aksi zona/flag/refresh | pakai `heatmap_version` dari response aksi → `getHeatmapChanges` |
| Flutter, foreground / sinyal kembali | `getHeatmapVersion` → jika beda, `getHeatmapChanges` |
| Flutter, mode berlayar & online | cek versi tiap 15 menit |
| Flutter, offline | pakai cache + tampilkan "Data per {generated_at}" |
| Flutter, push `zone_changed` diterima | langsung `getHeatmapChanges` (12.B.10) |
| Flutter, setiap request | kirim header `X-Heatmap-Version` |
| Setiap 1 menit (kedua klien) | hitung ulang `enforcement` semua zona dari data lokal (12.A.2), tanpa request |
| Setelah sinkron berhasil (Flutter) | validasi ulang rekomendasi lokal (12.B.5) |
| Respons `410` | muat ulang penuh: `getHeatmap` + `getZones` |

---

#### 12.A.5 Refresh heatmap

**Pemicu otomatis (wajib, dalam transaksi aksi terkait):**

| Peristiwa | Sel yang di-refresh |
|---|---|
| `createZona`, `editGridZona` | grid yang ditambah & dilepas |
| `editZona`, `editStatusZona` | semua grid anggota |
| `automaticFlagToRestricted`, `dismissFlag` | grid yang flag-nya berubah |
| Trip nelayan selesai | grid yang disentuh + tetangganya |
| Trip menyentuh zona `restricted` (kuota berkurang / habis) | tidak ada sel; `ZoneEntry` zona tersebut masuk `changed_zone_ids` |
| Worker harian | grid yang nilainya berubah; zona yang kuotanya direset |
| Zona mulai / berhenti berlaku (`effective_from` / `effective_until`) | **tidak menaikkan versi** — dihitung klien (12.A.2) |

Publish selalu atomik: tulis `heatmap_cells` + `zones` (kolom kuota/outline) + baris `heatmap_versions` dalam satu transaksi, lalu antre push (12.B.10) setelah commit.

##### `refreshHeatmap` — `POST /admin/heatmap/refresh`
Varian worker: `POST /internal/jobs/heatmap-refresh` (`X-Internal-Key`), body & response sama.

Request
```json
{ "scope": "all", "grid_ids": null, "zone_id": null, "recompute_fatigue": false, "reason": "Update data sebaran karang" }
```

| Field | Wajib | Aturan |
|---|---|---|
| `scope` | ✅ | `all` \| `grids` \| `zone` |
| `grid_ids` | jika `grids` | 1–5000 |
| `zone_id` | jika `zone` | zona aktif |
| `recompute_fatigue` | ❌ | true = hitung ulang fatigue dari `grid_daily_load` dengan parameter terbaru |
| `reason` | ✅ | 3–500 karakter |

- `grids` / `zone` → `200` sinkron:
```json
{ "data": { "status": "done", "heatmap_version": 1046, "changed_cells": 24, "finished_at": "2026-10-16T01:02:00Z" } }
```
- `all` → `202` asinkron:
```json
{ "data": { "status": "queued", "job_id": "f09a…", "status_url": "/api/v1/admin/heatmap/refresh/f09a…" } }
```
Error: `400`, `404 ZONE_NOT_FOUND`, `409 REFRESH_IN_PROGRESS`, `422 GRID_INVALID`.

##### `getRefreshStatus` — `GET /admin/heatmap/refresh/{job_id}`
```json
{
  "data": {
    "job_id": "f09a…", "status": "running", "progress_pct": 64,
    "heatmap_version": null, "changed_cells": null, "error": null,
    "started_at": "2026-10-16T01:00:00Z", "finished_at": null
  }
}
```
`status`: `queued` | `running` | `done` | `failed`. Next.js polling tiap 2 detik sampai `done`/`failed`. Error: `404 JOB_NOT_FOUND`.

---

#### 12.A.6 Grid

##### `getGridDetail` — `GET /admin/grids/{grid_id}`
```json
{
  "data": {
    "grid_id": "a40b120", "a": 40, "b": 120,
    "centroid": { "lat": -8.41, "lng": 112.70 },
    "is_sea": true, "has_coral": true, "coral_cover_pct": 35,
    "heatmap_version": 1044,
    "zone": null,
    "auto_flag": "restricted",
    "auto_flagged_at": "2026-10-16T17:10:04Z",
    "flag_dismissed_until": null,
    "stats": {
      "fatigue_index": 0.74, "fatigue_level": "critical", "pressure_index": 0.66,
      "trip_count_7d": 5, "trip_count_30d": 18,
      "fishing_hours_30d": 40.5, "catch_kg_30d": 160.0, "cpue_30d": 3.95,
      "last_visited_at": "2026-10-15T03:00:00Z"
    },
    "fatigue_trend_30d": [ ["2026-09-17", 0.41], ["2026-10-16", 0.74] ]
  }
}
```
- `zone` = `ZoneEntry` (tanpa outline) atau `null`.
- Semua angka di `stats`, `zone`, dan `auto_flag` dibaca dari **`heatmap_cells`** pada `heatmap_version` yang sama dengan heatmap, bukan dari `grid_stats`. `fatigue_trend_30d` dari `grid_daily_load`.
- Error: `404 GRID_NOT_FOUND`, `422 GRID_INVALID` (format ID salah).

---

#### 12.A.7 Zona

##### `previewZona` — `POST /admin/zones/preview`
Menghitung agregat & konflik **tanpa menyimpan**. Next.js memanggil dengan debounce ±400 ms setiap seleksi berubah.

Request
```json
{ "grid_ids": ["a12b34", "a12b35"], "exclude_zone_id": null }
```
`exclude_zone_id` = id zona yang sedang diedit (grid miliknya tidak dihitung konflik).

Response `200`
```json
{
  "data": {
    "valid_grid_ids": ["a12b34", "a12b35"],
    "invalid_grid_ids": [],
    "conflicts": [ { "grid_id": "a12b35", "zone_id": "51ab…", "zone_name": "Zona Lama" } ],
    "aggregate": { "...": "ZoneAggregate (quota = null)" },
    "outline": { "type": "MultiPolygon", "coordinates": [] },
    "is_contiguous": true,
    "heatmap_version": 1044
  }
}
```
`is_contiguous = false` → UI menampilkan peringatan grid terpisah (bagian 6.2). Batas `grid_ids`: 1–5000.

##### `createZona` — `POST /admin/zones`
Request
```json
{
  "name": "Karang Teluk Sendang Biru",
  "status": "restricted",
  "grid_ids": ["a12b34", "a12b35", "a13b34"],
  "rules": { "max_catch_kg_per_period": 500, "period": "weekly" },
  "effective_from": "2026-10-17T00:00:00Z",
  "effective_until": null,
  "reason": "Fatigue kritis di 6 grid berkoral",
  "note": null,
  "on_conflict": "reject"
}
```

| Field | Wajib | Aturan |
|---|---|---|
| `name` | ✅ | 3–100 karakter, unik (tanpa beda huruf besar/kecil) di antara zona aktif |
| `status` | ✅ | `restricted` \| `rehab`; `normal` ditolak |
| `grid_ids` | ✅ | 1–5000, unik, grid laut di dalam pilot |
| `rules` | jika `restricted` | `ZoneRules` |
| `effective_from` | ❌ | default sekarang |
| `effective_until` | ❌ | > `effective_from` |
| `reason` | ✅ | 3–500 karakter |
| `note` | ❌ | maks 2000 karakter |
| `on_conflict` | ❌ | `reject` (default) \| `move` \| `skip` |

Response `201`: `ZoneDetail` + `skipped_grid_ids`, `moved_grid_ids`.
Error: `400`, `409 ZONE_NAME_TAKEN`, `409 GRID_CONFLICT`, `422 GRID_INVALID`, `422 RULES_REQUIRED`, `422 ZONE_EMPTY` (semua grid ter-`skip`).

Efek samping (1 transaksi): insert `zones` + `zone_grids`; simpan `outline` & `bbox`; `zone_history (create)`; hapus auto-flag grid anggota; publish sel; naikkan `heatmap_version`. Zona lama yang kehilangan semua grid karena `move` → otomatis diarsipkan (`zone_history (archive)`). Setelah commit: antre push `zone_changed` (12.B.10).

**Notifikasi di response aksi zona.** `createZona`, `editZona` (aturan / masa berlaku), `editGridZona`, dan `editStatusZona` menambahkan field berikut ke response:
```json
{ "notification": { "change": "created", "queued_fishers": 37 } }
```
`queued_fishers` = jumlah nelayan penerima push (aturan penerima di 12.B.10). Kegagalan push **tidak** menggagalkan aksi zona.

##### `readListZona` — `GET /admin/zones`
| Query | Default | Keterangan |
|---|---|---|
| `status` | semua | `restricted` \| `rehab` |
| `q` | — | cari nama (ILIKE) |
| `sort` | `-updated_at` | `name`, `-fatigue_max`, `-fatigue_avg`, `-grid_count`, `-updated_at`, `-created_at` |
| `page`, `limit` | 1, 20 | — |
| `include_archived` | false | true = ikut zona yang sudah dibubarkan |

Response `200`
```json
{ "data": [ { "...": "ZoneSummary" } ], "meta": { "page": 1, "limit": 20, "total": 7, "heatmap_version": 1044 } }
```

##### `readDetailZona` — `GET /admin/zones/{id}`
Response `200`: `ZoneDetail`. Zona arsip tetap bisa dibuka (`is_active = false`). Error: `404 ZONE_NOT_FOUND`.

##### `editZona` — `PATCH /admin/zones/{id}`
Mengubah metadata & aturan **tanpa** mengubah status atau anggota grid. Semua field opsional kecuali `reason` dan `version`.

Request
```json
{
  "name": "Karang Sendang Biru Timur",
  "rules": { "max_catch_kg_per_period": 400, "period": "weekly" },
  "effective_from": null,
  "effective_until": "2027-01-01T00:00:00Z",
  "note": "…",
  "reason": "Penyesuaian kuota",
  "version": 2
}
```
- Field `status` / `grid_ids` ditolak (`400`).
- Mengubah `rules.period` mereset kuota periode berjalan.

Response `200`: `ZoneDetail`. Error: `400`, `404`, `409 ZONE_NAME_TAKEN`, `409 VERSION_CONFLICT`, `409 ZONE_ARCHIVED`.
Efek samping: `zone_history (update_meta / update_rules)`; refresh sel; naikkan `heatmap_version`.

##### `editGridZona` — `PATCH /admin/zones/{id}/grids`
Request
```json
{ "add": ["a12b36"], "remove": ["a13b34"], "on_conflict": "reject", "reason": "Perluasan area", "version": 2 }
```
- `add` dan `remove` tidak boleh beririsan; minimal salah satu diisi.
- Grid di `remove` yang bukan anggota diabaikan.

Response `200`: `ZoneDetail` + `skipped_grid_ids`, `moved_grid_ids`.
Error: `400`, `404`, `409 GRID_CONFLICT`, `409 VERSION_CONFLICT`, `409 ZONE_ARCHIVED`, `422 GRID_INVALID`, `422 ZONE_EMPTY` (gunakan `editStatusZona` ke `normal` untuk membubarkan).
Efek samping: `zone_history (add_grids / remove_grids)`; grid yang dilepas dievaluasi ulang auto-flag; refresh sel; naikkan `heatmap_version`.

##### `editStatusZona` — `PATCH /admin/zones/{id}/status`
Request
```json
{ "status": "normal", "reason": "Fatigue seluruh grid < 0.2 selama 30 hari", "rules": null, "effective_until": null, "version": 3 }
```

| Field | Wajib | Aturan |
|---|---|---|
| `status` | ✅ | `normal` \| `restricted` \| `rehab`, berbeda dari status sekarang |
| `reason` | ✅ | 3–500 karakter |
| `rules` | jika menjadi `restricted` dan zona belum punya aturan | `ZoneRules` |
| `effective_until` | ❌ | — |
| `version` | ✅ | — |

| Transisi | Efek |
|---|---|
| `restricted` → `rehab` | Aturan disimpan tapi tidak berlaku; larangan penuh |
| `rehab` → `restricted` | Aturan wajib ada; kuota periode berjalan direset |
| → `normal` | **Zona dibubarkan**: `is_active = false`, `archived_at = now`, snapshot `grid_ids` di `zone_history (archive)`, `zone_grids` dihapus, zona hilang dari `readListZona`, grid dilepas dievaluasi ulang auto-flag |

Response `200`
- ke `restricted` / `rehab`: `ZoneDetail`
- ke `normal`:
```json
{
  "data": {
    "id": "8f2c…", "status": "normal", "is_active": false,
    "archived_at": "2026-10-16T01:00:00Z",
    "released_grid_ids": ["a12b34", "a12b35", "a13b34"],
    "reflagged_grid_ids": [],
    "heatmap_version": 1045, "version": 4
  }
}
```
Error: `400`, `404`, `409 VERSION_CONFLICT`, `409 ZONE_ARCHIVED`, `422 RULES_REQUIRED`, `422 SAME_STATUS`.

---

#### 12.A.8 Flag

##### `automaticFlagToRestricted` — `POST /internal/jobs/auto-flag`
Dijalankan **sistem**: harian 00:10 WIB setelah perhitungan fatigue, dan setelah trip selesai (grid yang disentuh). Header `X-Internal-Key`.

| Kondisi | Aksi |
|---|---|
| Grid tidak di zona aktif, tidak di-dismiss, `fatigue_index ≥ flag.threshold_on` (0.7) | set `auto_flag = "restricted"`, `auto_flagged_at = now` |
| Grid ber-flag dan `fatigue_index < flag.threshold_off` (0.5) | hapus flag |
| Grid masuk zona aktif | hapus flag |
| `flag_dismissed_until` masih berlaku | tidak di-flag |

Request
```json
{ "grid_ids": ["a12b34"], "dry_run": false }
```
`grid_ids` kosong = semua grid laut.

Response `200`
```json
{
  "data": {
    "run_id": "c71e…", "evaluated": 144400,
    "flag_added": ["a40b120", "a40b121"], "flag_removed": ["a10b88"],
    "heatmap_version": 1044, "finished_at": "2026-10-16T17:10:04Z"
  }
}
```
`dry_run = true` → hasil dihitung tanpa disimpan, `heatmap_version` tidak naik.

##### `listFlags` — `GET /admin/flags`
| Query | Default | Keterangan |
|---|---|---|
| `state` | `active` | `active` \| `dismissed` |
| `has_coral` | — | filter |
| `bbox` | seluruh pilot | — |
| `sort` | `-fatigue` | `-fatigue`, `-flagged_at`, `flagged_at` |
| `page`, `limit` | 1, 20 | — |

Response `200`
```json
{
  "data": [
    {
      "grid_id": "a40b120", "a": 40, "b": 120,
      "centroid": { "lat": -8.41, "lng": 112.70 },
      "has_coral": true, "fatigue_index": 0.74, "fatigue_level": "critical",
      "flagged_at": "2026-10-16T17:10:04Z", "days_flagged": 3,
      "flagged_neighbor_ids": ["a40b121"],
      "dismissed_until": null, "dismiss_reason": null
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 12 }
}
```
`flagged_neighbor_ids` membantu admin memilih grid berdekatan sekaligus saat membuat zona.

##### `dismissFlag` — `POST /admin/flags/dismiss`
Admin menyatakan flag sudah ditinjau dan tidak perlu zona.

Request
```json
{ "grid_ids": ["a40b120"], "until": "2026-11-15T00:00:00Z", "reason": "Area pemijahan musiman, tekanan wajar" }
```

| Field | Wajib | Aturan |
|---|---|---|
| `grid_ids` | ✅ | 1–5000 |
| `until` | ❌ | default +30 hari, maks +180 hari |
| `reason` | ✅ | 3–500 karakter |

Response `200`
```json
{ "data": { "dismissed_grid_ids": ["a40b120"], "skipped_grid_ids": [], "until": "2026-11-15T00:00:00Z", "heatmap_version": 1047 } }
```
`skipped_grid_ids` = grid yang tidak sedang ber-flag. Setelah `until` lewat, grid dievaluasi lagi pada run auto-flag berikutnya.

---

#### 12.A.9 Audit & statistik

##### `zoneHistory` — `GET /admin/zones/{id}/history`
| Query | Default |
|---|---|
| `action` | semua |
| `page`, `limit` | 1, 20 |

Response `200`: `{ "data": [ ZoneHistoryItem ], "meta": { … } }`, urut terbaru. Zona arsip tetap bisa dibuka. Error: `404 ZONE_NOT_FOUND`.

##### `statsSummary` — `GET /admin/stats/summary`
| Query | Default |
|---|---|
| `window` | `30d` (`7d` \| `30d`) |

Response `200`
```json
{
  "data": {
    "window": "30d",
    "zones": { "restricted": 4, "rehab": 3, "protected_area_km2": 42.5 },
    "flags": { "active": 12, "dismissed": 2 },
    "trips": { "count": 318, "catch_kg": 9120.0, "active_fishers": 57 },
    "coral_fatigue_distribution": { "healthy": 410, "tired": 96, "critical": 21 },
    "top_fatigued_zones": [ { "id": "…", "name": "…", "status": "rehab", "fatigue_avg": 0.81 } ],
    "top_flagged_grids": [ { "grid_id": "a40b120", "fatigue_index": 0.88 } ],
    "violations": { "count": 6, "by_zone": [ { "zone_id": "…", "name": "…", "count": 4 } ] },
    "sync_coverage": {
      "active_fishers_7d": 57,
      "on_latest_version": 44,
      "on_latest_pct": 77.2,
      "behind": [ { "bucket": "1-5 versi", "count": 9 }, { "bucket": "> 5 versi", "count": 4 } ],
      "push_enabled_fishers": 51
    },
    "heatmap_version": 1047,
    "generated_at": "2026-10-16T01:05:00Z"
  }
}
```
`top_*` maks 5 item. `violations` dipakai untuk edukasi, bukan penalti. `sync_coverage` dihitung dari `users.last_heatmap_version` & `last_seen_at` (12.B.10).

---

#### 12.A.10 Ringkasan endpoint admin

| # | Nama | Method | Path | Pemanggil | Prioritas |
|---|---|---|---|---|---|
| 1 | login | POST | `/auth/login` | Next.js & Flutter | MUST |
| 2 | me | GET | `/me` | Next.js & Flutter | MUST |
| 3 | getGridMeta | GET | `/map/grid-meta` | SHARED | MUST |
| 4 | getSeaMask | GET | `/map/sea-mask` | SHARED | MUST |
| 5 | getZones | GET | `/map/zones` | SHARED | MUST |
| 6 | getHeatmap | GET | `/map/heatmap` | SHARED | MUST |
| 7 | getHeatmapVersion | GET | `/map/heatmap/version` | SHARED | MUST |
| 8 | getHeatmapChanges | GET | `/map/heatmap/changes` | SHARED | MUST |
| 9 | getWeatherArea | GET | `/weather/area` | SHARED | MUST |
| 10 | refreshHeatmap | POST | `/admin/heatmap/refresh` | Next.js | MUST |
| 11 | refreshHeatmap (worker) | POST | `/internal/jobs/heatmap-refresh` | Worker | MUST |
| 12 | getRefreshStatus | GET | `/admin/heatmap/refresh/{job_id}` | Next.js | MUST |
| 13 | getGridDetail | GET | `/admin/grids/{grid_id}` | Next.js | MUST |
| 14 | previewZona | POST | `/admin/zones/preview` | Next.js | MUST |
| 15 | createZona | POST | `/admin/zones` | Next.js | MUST |
| 16 | readListZona | GET | `/admin/zones` | Next.js | MUST |
| 17 | readDetailZona | GET | `/admin/zones/{id}` | Next.js | MUST |
| 18 | editZona | PATCH | `/admin/zones/{id}` | Next.js | MUST |
| 19 | editGridZona | PATCH | `/admin/zones/{id}/grids` | Next.js | MUST |
| 20 | editStatusZona | PATCH | `/admin/zones/{id}/status` | Next.js | MUST |
| 21 | automaticFlagToRestricted | POST | `/internal/jobs/auto-flag` | Worker | MUST |
| 22 | listFlags | GET | `/admin/flags` | Next.js | SHOULD |
| 23 | dismissFlag | POST | `/admin/flags/dismiss` | Next.js | SHOULD |
| 24 | zoneHistory | GET | `/admin/zones/{id}/history` | Next.js | SHOULD |
| 25 | statsSummary | GET | `/admin/stats/summary` | Next.js | SHOULD |

#### 12.A.11 Happy path admin (urutan panggilan)

```
1. login                → simpan JWT di cookie httpOnly (tolak jika role ≠ admin)
2. me                   → tampilkan nama admin
3. getGridMeta + getSeaMask + getHeatmap + getZones   → render peta (cache + heatmap_version); hitung enforcement zona tiap 1 menit
4. hover grid           → tooltip dari data heatmap lokal (tanpa request)
5. klik grid            → getGridDetail
6. pilih beberapa grid  → previewZona (debounce) → tampilkan agregat & konflik
7. isi nama + status    → createZona → ambil heatmap_version → getHeatmapChanges
8. buka daftar zona     → readListZona → klik → readDetailZona (+ zoneHistory)
9. ubah kuota/nama      → editZona;  tambah/kurangi grid → previewZona(exclude_zone_id) → editGridZona
10. zona pulih          → editStatusZona(normal) → zona hilang dari list, heatmap diperbarui, push ke nelayan
10b. cek jangkauan     → readDetailZona.sync.known_by_pct / statsSummary.sync_coverage
11. latar belakang      → tiap 60 dtk getHeatmapVersion → getHeatmapChanges jika berubah
```

---

### 12.B Kontrak API Nelayan (lengkap)

Kontrak ini mengikat **BE (Go Gin)** dan **Mobile (Flutter)**. Konvensi, envelope, paginasi, dan kode error umum mengikuti **12.A.1**. Endpoint peta & cuaca **SHARED** didefinisikan di **12.A.4** dan dipakai Flutter apa adanya.

Semua endpoint di bagian ini (kecuali `register` & `login`) membutuhkan JWT `role = fisher`.

#### 12.B.0 Prinsip

- **Satu kapal di MVP.** Kapal diisi sekali saat onboarding dan otomatis menjadi kapal default. Skema sudah mendukung banyak kapal untuk fase 2 (12.B.11).
- **Snapshot spesifikasi kapal di setiap trip.** Mengubah kapal tidak mengubah data trip lama, sehingga data latih ML tetap benar.
- **Trip dikirim sekali, setelah selesai.** Onboarding, input manual, dan mode berlayar memakai satu endpoint `postTrip`. Tracking, deteksi berhenti, dan auto-flag radius berjalan offline di HP (bagian 9); hasilnya dikirim utuh saat pelayaran selesai.
- **Idempoten.** Setiap trip membawa `client_trip_id` buatan HP. Kiriman ulang karena sinyal putus tidak membuat trip ganda.
- **Batasan & heatmap sama dengan admin.** Flutter memakai `getZones` dan `getHeatmap` SHARED (12.A.4).

#### 12.B.1 Kode error tambahan

| HTTP | `code` | Kapan |
|---|---|---|
| 400 | `INVALID_PHONE` | Format no. telp bukan nomor seluler Indonesia |
| 404 | `BOAT_NOT_FOUND`, `TRIP_NOT_FOUND` | Data tidak ada / bukan milik user |
| 409 | `PHONE_TAKEN` | No. telp sudah terdaftar |
| 409 | `BOAT_LIMIT_REACHED` | MVP: nelayan sudah punya 1 kapal |
| 409 | `ONBOARDING_REQUIRED` | Meminta rekomendasi sebelum onboarding selesai |
| 409 | `ALREADY_ONBOARDED` | Mengirim trip `source = onboarding` kedua kali |
| 422 | `WEAK_PASSWORD` | Password < 8 karakter |
| 422 | `BOAT_REQUIRED` | Mengirim trip sebelum kapal diisi |
| 422 | `OUT_OF_PILOT` | Titik di luar area pilot / titik tangkap di daratan (`details.points`) |
| 422 | `INVALID_TIME_RANGE` | Urutan / rentang waktu trip tidak valid |
| 404 | `DEVICE_NOT_FOUND` | `device_id` tidak ada / bukan milik user |

#### 12.B.2 Objek bersama

**`Boat`**
```json
{
  "id": "b1c2…",
  "name": "KM Sumber Rejeki",
  "engine_hp": 15,
  "boat_length_m": 7,
  "fuel_type": "solar",
  "home_port": { "lat": -8.43, "lng": 112.68 },
  "is_default": true,
  "created_at": "2026-10-16T00:00:00Z",
  "updated_at": "2026-10-16T00:00:00Z"
}
```

**`FishingPoint`**
```json
{
  "lat": -8.30, "lng": 112.60,
  "started_at": "2026-10-15T22:10:00Z",
  "ended_at": "2026-10-16T01:30:00Z",
  "flag_source": "rec_radius",
  "recommendation_id": "r9a1…",
  "reported_catch_kg": null
}
```
- `flag_source`: `manual` | `user_confirmed` | `auto_timeout` | `rec_radius` (bagian 9.2).
- `recommendation_id` wajib jika `flag_source = rec_radius`.
- `reported_catch_kg` opsional (Open Question 6). Jika diisi di semua titik, BE memakainya; jika tidak, `catch_kg` trip dibagi proporsional durasi, lalu dibagi rata.

**`TrackPoint`** (hanya `source = sailing`)
```json
{ "seq": 1, "lat": -8.43, "lng": 112.68, "recorded_at": "2026-10-15T21:00:00Z", "speed_ms": 3.1, "accuracy_m": 8 }
```

**`Recommendation`**
```json
{
  "id": "r9a1…",
  "type": "fuel_saving",
  "grid_id": "a142b217",
  "point": { "lat": -8.31, "lng": 112.62 },
  "zone": { "id": null, "name": null, "status": "normal" },
  "zone_rules": null,
  "area_condition": "healthy",
  "predicted_fuel_liters": 18.2,
  "fuel_efficiency_pct": 28.6,
  "predicted_catch_kg": 35.0,
  "predicted_catch_range_kg": [25.0, 45.0],
  "departure_time": "04:30",
  "return_time": "11:00",
  "for_date": "2026-10-17",
  "distance_from_port_km": 14.3,
  "weather_summary": { "wind_speed_ms": 4.2, "wind_dir_deg": 120, "wind_dir_label": "TG", "wave_height_m": 0.8, "temp_c": 28, "risk": "low" },
  "confidence": 0.62,
  "reason": "Jarak dekat, angin mendukung saat berangkat, kondisi area sehat"
}
```
- `zone.status`: `normal` (tanpa zona) | `restricted`. Zona `rehab` tidak pernah muncul.
- `zone` = ringkasan `{ id, name, status }`; `zone_rules` diisi jika `restricted`: `{ "quota_remaining_kg": 120, "open_schedule": { … } }`. Status buka dihitung klien dengan aturan 12.A.2 — tidak ada `open_now`.
- `area_condition`: `healthy` | `tired` (grid `critical` tidak pernah direkomendasikan, bagian 10.2).

**`RecommendationSet`**
```json
{
  "for_date": "2026-10-17",
  "generated_at": "2026-10-16T05:00:00Z",
  "valid_until": "2026-10-16T11:00:00Z",
  "source_trip_id": "t71…",
  "boat_id": "b1c2…",
  "baseline_fuel_liters": 25.5,
  "heatmap_version": 1044,
  "model_version": "rec-0.2.0",
  "is_fallback": false,
  "items": [ { "...": "Recommendation (fuel_saving)" }, { "...": "catch_max" }, { "...": "balanced" }, { "...": "habitual" } ],
  "unavailable_types": []
}
```
- `items` diurutkan `fuel_saving`, `catch_max`, `balanced`, `habitual`.
- Tipe tanpa kandidat valid masuk `unavailable_types`: `[{ "type": "habitual", "reason_code": "NO_VALID_CANDIDATE" }]`.
- `is_fallback = true` → dihasilkan heuristik BE karena ML tidak merespons; Flutter menampilkan label "Perkiraan sederhana".
- `heatmap_version` = versi data zona & heatmap yang dipakai saat set dibuat.

**`TripSummary`** (item riwayat)
```json
{
  "id": "t71…",
  "source": "sailing",
  "departed_at": "2026-10-15T21:00:00Z",
  "returned_at": "2026-10-16T05:00:00Z",
  "duration_h": 8.0,
  "fuel_liters": 25.5,
  "catch_kg": 40.0,
  "distance_from_port_km": 14.3,
  "total_distance_km": 31.2,
  "fuel_efficiency_pct": 4.2,
  "catch_per_liter": 1.57,
  "fishing_point_count": 2,
  "main_grid_id": "a142b217",
  "followed_recommendation_type": "fuel_saving",
  "zone_violation": false,
  "boat": { "id": "b1c2…", "name": "KM Sumber Rejeki" }
}
```

**`TripDetail`** = `TripSummary` +
```json
{
  "client_trip_id": "c0ffee…",
  "departure": { "lat": -8.43, "lng": 112.68 },
  "return_point": { "lat": -8.43, "lng": 112.68 },
  "fishing_hours": 5.3,
  "fuel_per_km": 0.82,
  "boat_snapshot": { "engine_hp": 15, "boat_length_m": 7 },
  "fishing_points": [
    {
      "id": "fp1…", "lat": -8.30, "lng": 112.60, "grid_id": "a142b217",
      "zone_at_time": { "id": null, "name": null, "status": "normal" },
      "started_at": "…", "ended_at": "…", "fishing_hours": 3.3,
      "allocated_catch_kg": 25.0, "flag_source": "rec_radius", "recommendation_id": "r9a1…"
    }
  ],
  "track": { "type": "LineString", "coordinates": [[112.68, -8.43], [112.65, -8.38]] },
  "selected_recommendation": { "id": "r9a1…", "type": "fuel_saving", "distance_to_point_m": 120 },
  "notes": null,
  "created_at": "2026-10-16T05:10:00Z"
}
```
- `zone_at_time` = status zona saat trip, bukan saat ini (riwayat tidak berubah ketika admin mengubah zona).
- `fuel_efficiency_pct` trip = `(baseline_fuel − fuel_liters) / baseline_fuel × 100`, baseline dihitung dari trip sebelumnya (trip onboarding = 0).

---

#### 12.B.3 Auth & profil

##### `register` — `POST /auth/register`
Publik. Tanpa OTP / verifikasi. Rate limit 3 akun / jam per IP.

Request
```json
{ "name": "Pak Darto", "phone": "081234567890", "password": "rahasia123" }
```

| Field | Aturan |
|---|---|
| `name` | 2–100 karakter |
| `phone` | Diterima `08…`, `628…`, `+628…`; dinormalisasi ke `+628…`; 10–14 digit |
| `password` | Min 8 karakter; disimpan bcrypt cost 12 |

Response `201`
```json
{
  "data": {
    "token": "eyJ…",
    "expires_at": "2026-10-23T00:00:00Z",
    "user": { "id": "…", "name": "Pak Darto", "phone": "+6281234567890", "role": "fisher", "onboarded": false }
  }
}
```
Error: `400 VALIDATION_ERROR`, `400 INVALID_PHONE`, `409 PHONE_TAKEN`, `422 WEAK_PASSWORD`, `429 TOO_MANY_ATTEMPTS`.
Selalu membuat role `fisher`; field `role` di body diabaikan.

##### `login` — `POST /auth/login`
Kontrak sama dengan **12.A.3**. Flutter **menolak** (tidak menyimpan token) jika `role = admin` dan menampilkan "Gunakan dashboard web".

##### `me` — `GET /me`
Response `200`
```json
{
  "data": {
    "id": "…", "name": "Pak Darto", "phone": "+6281234567890", "role": "fisher",
    "onboarded": true,
    "next_step": "done",
    "boat": { "...": "Boat (default) | null" },
    "stats": { "trip_count": 5, "baseline_fuel_liters": 25.5, "baseline_catch_kg": 40.0, "last_trip_at": "2026-10-16T05:00:00Z" }
  }
}
```
`next_step` mengarahkan layar setelah login / buka aplikasi:
- `boat` → belum ada kapal → layar isi kapal
- `first_trip` → kapal ada, belum ada trip onboarding → layar trip pertama
- `done` → dashboard

##### `createBoat` — `POST /me/boats`
Dipakai **sekali** saat onboarding (MVP).

Request
```json
{ "name": "KM Sumber Rejeki", "engine_hp": 15, "boat_length_m": 7, "fuel_type": "solar", "home_port": { "lat": -8.43, "lng": 112.68 } }
```

| Field | Wajib | Aturan |
|---|---|---|
| `name` | ❌ | maks 60 karakter |
| `engine_hp` | ✅ | 1–500 |
| `boat_length_m` | ✅ | 2–30 |
| `fuel_type` | ❌ | `solar` (default) \| `bensin` |
| `home_port` | ✅ | dalam bounding box pilot (+5 km toleransi darat untuk dermaga) |

Response `201`: `Boat` (`is_default = true`).
Error: `400`, `409 BOAT_LIMIT_REACHED`, `422 OUT_OF_PILOT`.

##### `updateBoat` — `PATCH /me/boats/{id}`
Memperbaiki spesifikasi kapal (mis. salah ketik saat onboarding). Semua field opsional, aturan sama dengan `createBoat`.

Response `200`: `Boat`. Error: `400`, `404 BOAT_NOT_FOUND`, `422 OUT_OF_PILOT`.
Efek: rekomendasi berikutnya memakai spesifikasi baru; trip lama tidak berubah (snapshot); cache rekomendasi user dihapus.

---

#### 12.B.4 Trip

##### `postTrip` — `POST /trips`
Satu endpoint untuk onboarding, input manual, dan akhir mode berlayar.

Request
```json
{
  "client_trip_id": "c0ffee00-0000-4000-8000-000000000001",
  "source": "sailing",
  "departure": { "lat": -8.43, "lng": 112.68 },
  "return_point": { "lat": -8.43, "lng": 112.68 },
  "departed_at": "2026-10-15T21:00:00Z",
  "returned_at": "2026-10-16T05:00:00Z",
  "fuel_liters": 25.5,
  "catch_kg": 40.0,
  "fishing_points": [ { "...": "FishingPoint" } ],
  "track": [ { "...": "TrackPoint" } ],
  "selected_recommendation_id": "r9a1…",
  "notes": null
}
```

| Field | Wajib | Aturan |
|---|---|---|
| `client_trip_id` | ✅ | UUID v4 buatan HP; unik per user |
| `source` | ✅ | `onboarding` \| `manual` \| `sailing` |
| `departure` | ❌ | default `boat.home_port`; dalam pilot (+5 km toleransi) |
| `return_point` | ❌ | default `departure` |
| `departed_at`, `returned_at` | ✅ | `returned_at > departed_at`, durasi ≤ 72 jam, `returned_at` ≤ sekarang + 10 menit |
| `fuel_liters` | ✅ | 0 < x ≤ 500 |
| `catch_kg` | ✅ | 0 ≤ x ≤ 5000 |
| `fishing_points` | ✅ | 1–50 titik, semua di grid laut dalam pilot; waktu (jika ada) di dalam rentang trip; `ended_at > started_at` |
| `track` | jika `sailing` | 2–5000 titik, `seq` unik & naik, `recorded_at` di dalam rentang trip (±10 menit) |
| `selected_recommendation_id` | ❌ | rekomendasi milik user; dipakai untuk evaluasi kepatuhan |
| `notes` | ❌ | maks 500 karakter |

Aturan per `source`:
- `onboarding` → hanya boleh sekali (`409 ALREADY_ONBOARDED`); setelah tersimpan, `users.onboarded = true`.
- `manual` / `sailing` → hanya setelah onboarding (`409 ONBOARDING_REQUIRED`).
- Semua → kapal default harus ada (`422 BOAT_REQUIRED`); `boat_id` di body diabaikan di MVP.

Query: `with_recommendations` (default `true`). `false` dipakai Flutter saat sinkron trip lama yang tertunda, agar tidak membuat rekomendasi usang.

Response `201`
```json
{
  "data": {
    "trip": { "...": "TripDetail" },
    "recommendations": { "...": "RecommendationSet | null" },
    "user": { "onboarded": true }
  }
}
```

**Idempoten:** `client_trip_id` yang sama dikirim ulang → `200` dengan body identik dan header `Idempotent-Replay: true`. Tidak ada data yang ditulis ulang.

Error: `400`, `409 ALREADY_ONBOARDED`, `409 ONBOARDING_REQUIRED`, `422 BOAT_REQUIRED`, `422 OUT_OF_PILOT`, `422 INVALID_TIME_RANGE`.

**Diturunkan BE saat simpan:**
- `grid_id` dan `zone_at_time` tiap titik tangkap (rumus 5.1).
- `distance_from_port_km` = dermaga → titik tangkap pertama (lewat track bila ada, garis lurus bila tidak).
- `total_distance_km` = panjang track (sailing) atau dermaga → titik-titik → `return_point` (manual/onboarding).
- `duration_h`, `fishing_hours` per titik & total, `fuel_per_km`, `catch_per_liter`, `fuel_efficiency_pct`.
- `allocated_catch_kg` per titik (aturan di `FishingPoint`).
- `zone_violation` = ada titik di zona `rehab` saat trip.
- Snapshot `engine_hp` & `boat_length_m` dari kapal default.

**Efek samping:**
- Sinkron (dalam transaksi): simpan trip, titik tangkap, track.
- Rekomendasi: dibuat sinkron untuk respons (timeout ML 3 detik → fallback heuristik, `is_fallback = true`).
- Asinkron via worker (≤ 1 menit): `grid_daily_load`, `zone_quota_usage`, `grid_stats`, auto-flag grid terdampak, refresh `heatmap_cells`, naikkan `heatmap_version`.

##### `getHistoryTrip` — `GET /trips`
| Query | Default | Keterangan |
|---|---|---|
| `page`, `limit` | 1, 20 | — |
| `from`, `to` | — | filter `departed_at` (tanggal WIB) |
| `source` | semua | `onboarding` \| `manual` \| `sailing` |
| `sort` | `-departed_at` | `-departed_at`, `departed_at`, `-catch_kg`, `-fuel_efficiency_pct` |

Response `200`
```json
{
  "data": [ { "...": "TripSummary" } ],
  "meta": { "page": 1, "limit": 20, "total": 12 },
  "summary": { "trip_count": 12, "total_catch_kg": 480.0, "total_fuel_liters": 290.0, "avg_catch_per_liter": 1.66 }
}
```
`summary` dihitung untuk seluruh hasil filter, bukan hanya halaman ini.

##### `getTripDetail` — `GET /trips/{id}`
| Query | Default | Keterangan |
|---|---|---|
| `track` | `simplified` | `simplified` (Douglas-Peucker ±20 m) \| `full` \| `none` |

Response `200`: `TripDetail`. Error: `404 TRIP_NOT_FOUND` (termasuk trip milik user lain).

---

#### 12.B.5 Rekomendasi

##### `getRecommendation` — `GET /recommendations`
Mengembalikan set rekomendasi untuk satu tanggal. Hasil di-cache; BE membuat ulang hanya bila perlu.

| Query | Default | Keterangan |
|---|---|---|
| `for_date` | hari ini (WIB) | `YYYY-MM-DD`, maks +2 hari (batas forecast cuaca) |
| `refresh` | false | true = paksa buat ulang |

**Kapan BE membuat ulang** (selain `refresh = true`):
- belum ada set untuk `for_date`, atau
- `valid_until` sudah lewat (default 6 jam sejak dibuat), atau
- ada zona yang memuat grid rekomendasi berubah status / kuotanya habis, atau
- kapal diubah (`updateBoat`).

Response `200`: `RecommendationSet`.
Error: `400` (`for_date` di luar rentang), `409 ONBOARDING_REQUIRED`.

Offline: Flutter memakai set terakhir dari cache lokal dan menampilkan "Dibuat {generated_at}". Set ini juga menjadi **titik target auto-flag radius** di mode berlayar (bagian 9.2).

**Validasi rekomendasi lokal (wajib di Flutter)** — dijalankan setiap kali data zona lokal berubah (setelah `getHeatmapChanges` / push) dan setiap 1 menit:
1. Untuk tiap rekomendasi, cari zona grid-nya dari cache lokal dan hitung `enforcement` pada `departure_time`–`return_time` (12.A.2).
2. Jika `closed`, atau grid kini ber-`fatigue_level = critical` → tandai **tidak berlaku**: kartu digaris abu "Area ini baru saja dibatasi", marker disembunyikan, tombol "Mulai Berlayar" dimatikan.
3. Jika online → panggil `getRecommendation` (server sudah otomatis membuat ulang karena zona berubah).
4. Rekomendasi tidak berlaku **tidak boleh** menjadi target auto-flag radius.

---

#### 12.B.6 Batasan (`getConstraint`)

Memakai **`getZones` — `GET /map/zones`** (12.A.4) untuk muat awal, lalu **`getHeatmapChanges`** (`zones_upserted` / `zones_removed`) untuk pembaruan. Bentuk data = `ZoneEntry`, sama persis dengan admin.

Aturan pemakaian di Flutter:
- Muat awal: `getZones(include_outline=true)`. Setelah itu tidak perlu memanggil `getZones` lagi kecuali cache hilang atau respons `410`.
- Simpan lokal: daftar `ZoneEntry` + indeks `grid_id → zone_id` (dibangun dari `grid_ids`).
- Peringatan masuk zona saat offline: hitung ID grid dari GPS (5.1) → cari `zone_id` → hitung `enforcement` (12.A.2). Peringatan muncul untuk `closed`; info kuota untuk `limited`.
- Jangan menyimpan `enforcement` sebagai data; selalu hitung ulang dari `ZoneEntry` + jam sekarang.

---

#### 12.B.7 Heatmap (`getHeatmap`)

Memakai endpoint **SHARED 12.A.4** apa adanya: `getGridMeta`, `getSeaMask`, `getHeatmap`, `getHeatmapVersion`, `getHeatmapChanges`. Response identik dengan admin. Aturan sinkron Flutter ada di tabel "Perilaku klien heatmap" 12.A.4.

Bottom sheet saat grid diketuk diisi dari data heatmap lokal (metrik + `ZoneEntry` + `enforcement`) dan `getWeatherInfo` — tanpa endpoint detail grid khusus nelayan. Angkanya sama dengan yang dilihat admin pada `heatmap_version` yang sama.

---

#### 12.B.8 Cuaca (`getWeatherInfo`)

##### `getWeatherInfo` — `GET /weather`
Cuaca di satu titik (posisi user, dermaga, atau grid yang diketuk). Diambil dari `weather_cache` sel sampel terdekat.

| Query | Wajib | Keterangan |
|---|---|---|
| `lat`, `lng` | ✅ | dalam pilot |
| `hours` | ❌ | jumlah jam forecast, default 24, maks 48 |

Response `200`
```json
{
  "data": {
    "location": { "lat": -8.40, "lng": 112.60, "cell_key": "c03_07" },
    "fetched_at": "2026-10-16T05:00:00Z",
    "current": {
      "time": "2026-10-16T05:00:00Z",
      "weather_code": 2, "weather_label": "Berawan sebagian",
      "temp_c": 28.1,
      "wind_speed_ms": 4.2, "wind_dir_deg": 120, "wind_dir_label": "TG",
      "wave_height_m": 0.8,
      "risk": "low"
    },
    "hourly": [
      { "time": "2026-10-16T06:00:00Z", "weather_code": 2, "temp_c": 28.4, "wind_speed_ms": 4.6, "wind_dir_deg": 125, "wind_dir_label": "TG", "wave_height_m": 0.9, "risk": "low" }
    ],
    "warnings": []
  }
}
```
- `risk` mengikuti ambang bagian 15.
- `warnings` berisi jam ber-`risk = high` dalam rentang forecast: `[{ "from": "…", "to": "…", "reason": "Gelombang > 2 m" }]`.
- Error: `400`, `422 OUT_OF_PILOT`.

Untuk panah angin di peta, pakai `getWeatherArea` (12.A.4).

---

#### 12.B.9 Konfigurasi mobile (SHOULD)

##### `getMobileConfig` — `GET /config/mobile`
Ambang mode berlayar & sinkronisasi, agar bisa diubah tanpa rilis ulang aplikasi. Boleh tanpa JWT. `ETag` + `304`.
```json
{
  "data": {
    "version": 3,
    "sailing": {
      "poll_interval_s": 120,
      "poll_interval_near_target_s": 30,
      "near_target_distance_m": 2000,
      "stop_distance_m": 50,
      "stop_speed_ms": 0.5,
      "stop_confirm_timeout_s": 300,
      "rec_radius_m": 500,
      "rec_radius_exit_buffer_m": 100
    },
    "sync": { "heatmap_check_interval_sailing_s": 900 },
    "limits": { "max_track_points": 5000, "max_fishing_points": 50 }
  }
}
```
Flutter menyimpan nilai terakhir; bila belum pernah mengambil, pakai nilai default di atas.

---

#### 12.B.10 Push notification & cakupan sinkron (SHOULD)

Tujuan: perubahan zona oleh admin sampai ke HP nelayan **dalam hitungan detik** begitu ada sinyal, tanpa menunggu aplikasi dibuka atau jeda cek 15 menit; dan admin bisa melihat berapa nelayan yang sudah memegang data terbaru.

##### `registerDevice` — `POST /me/devices`
Dipanggil setelah login dan setiap kali token FCM diperbarui. Upsert berdasarkan `fcm_token` (jika token sebelumnya milik user lain di HP yang sama, dipindahkan ke user ini).

Request
```json
{ "fcm_token": "dK3…", "platform": "android", "app_version": "1.0.3" }
```
Response `200`
```json
{ "data": { "device_id": "d7e1…", "push_enabled": true } }
```
Error: `400`.

##### `unregisterDevice` — `DELETE /me/devices/{device_id}`
Dipanggil saat logout, agar push zona tidak dikirim ke HP yang sudah keluar akun. Response `204`. Error: `404 DEVICE_NOT_FOUND`.

##### Push `zone_changed` (BE → Flutter, FCM)
Dikirim worker dari `push_outbox` setelah aksi zona commit.

| `change` | Pemicu | Prioritas FCM |
|---|---|---|
| `created` | `createZona` | high |
| `status_changed` | `editStatusZona` ke `restricted` / `rehab` | high |
| `grids_added` | `editGridZona` dengan `add` | high |
| `rules_changed` | `editZona` mengubah aturan / masa berlaku | normal |
| `quota_exhausted` | kuota zona `restricted` habis | high |
| `dissolved` | `editStatusZona` ke `normal` | normal |

Payload (data message + notifikasi tampil)
```json
{
  "data": {
    "type": "zone_changed",
    "change": "status_changed",
    "zone_id": "8f2c…",
    "zone_name": "Karang Teluk Sendang Biru",
    "status": "rehab",
    "heatmap_version": "1045"
  },
  "notification": { "title": "Zona berubah: Karang Teluk Sendang Biru", "body": "Sekarang rehab penuh — dilarang menangkap ikan." }
}
```
- Flutter: saat menerima `zone_changed` → `getHeatmapChanges(since = versi lokal)` → validasi rekomendasi lokal (12.B.5). Jika offline, push FCM tertahan dan tiba saat sinyal kembali.
- **Penerima:** nelayan dengan perangkat terdaftar yang (a) `home_port` kapal default-nya dalam `rec.max_range_km` (40 km) dari `bbox` zona, **atau** (b) punya titik tangkap di grid zona tersebut dalam 30 hari terakhir.
- **Penggabungan:** maksimal 1 push per zona per nelayan per 10 menit; perubahan beruntun digabung ke push terakhir.
- Token yang ditolak FCM (`UNREGISTERED`) dihapus otomatis.

##### Cakupan sinkron (`X-Heatmap-Version`)
- Flutter mengirim header `X-Heatmap-Version: <versi lokal>` di **setiap** request (12.A.1).
- Middleware Go menyimpan `users.last_heatmap_version` (nilai terbesar) dan `last_seen_at`, maksimal 1 tulis per user per menit.
- **Nelayan aktif** = `last_seen_at` dalam 7 hari terakhir.
- Dipakai di `statsSummary.sync_coverage` (seluruh pilot) dan `readDetailZona.sync` (per zona: `last_heatmap_version ≥ changed_in_heatmap_version`).

---

#### 12.B.11 Fase 2: banyak kapal (belum diimplementasikan)

Skema DB sudah mendukung; yang berubah hanya aturan BE.

| Endpoint | Fungsi |
|---|---|
| `GET /me/boats` | Daftar kapal (tanpa yang dihapus) |
| `DELETE /me/boats/{id}` | Soft delete (`deleted_at`); kapal default tidak bisa dihapus selama masih satu-satunya |
| `PUT /me/boats/{id}/default` | Jadikan default |
| `POST /me/boats` | Batas 1 kapal dilepas |
| `POST /trips` + `boat_id` | Opsional; kosong = kapal default |
| `GET /recommendations` + `boat_id` | Opsional; kosong = kapal default |

---

#### 12.B.12 Ringkasan endpoint nelayan

| # | Nama | Method | Path | Prioritas |
|---|---|---|---|---|
| 1 | register | POST | `/auth/register` | MUST |
| 2 | login | POST | `/auth/login` (12.A.3) | MUST |
| 3 | me | GET | `/me` | MUST |
| 4 | createBoat | POST | `/me/boats` | MUST |
| 5 | updateBoat | PATCH | `/me/boats/{id}` | MUST |
| 6 | postTrip | POST | `/trips` | MUST |
| 7 | getHistoryTrip | GET | `/trips` | MUST |
| 8 | getTripDetail | GET | `/trips/{id}` | MUST |
| 9 | getRecommendation | GET | `/recommendations` | MUST |
| 10 | getConstraint (getZones) | GET | `/map/zones` (12.A.4) | MUST |
| 11 | getGridMeta | GET | `/map/grid-meta` (12.A.4) | MUST |
| 12 | getSeaMask | GET | `/map/sea-mask` (12.A.4) | MUST |
| 13 | getHeatmap | GET | `/map/heatmap` (12.A.4) | MUST |
| 14 | getHeatmapVersion | GET | `/map/heatmap/version` (12.A.4) | MUST |
| 15 | getHeatmapChanges | GET | `/map/heatmap/changes` (12.A.4) | MUST |
| 16 | getWeatherInfo | GET | `/weather` | MUST |
| 17 | getWeatherArea | GET | `/weather/area` (12.A.4) | MUST |
| 18 | getMobileConfig | GET | `/config/mobile` | SHOULD |
| 19 | registerDevice | POST | `/me/devices` | SHOULD |
| 20 | unregisterDevice | DELETE | `/me/devices/{device_id}` | SHOULD |

#### 12.B.13 Happy path nelayan (urutan panggilan)

```
ONBOARDING
1. register              → simpan token
2. me                    → next_step = "boat"
3. createBoat            → isi kapal sekali (HP mesin, panjang, dermaga)
4. postTrip(onboarding)  → trip baseline → response berisi RecommendationSet
5. tampilkan 4 rekomendasi → me.next_step = "done"

BUKA DASHBOARD
6. registerDevice (token FCM) + getMobileConfig + getGridMeta + getSeaMask (cache)
7. getHeatmap + getZones (muat awal, cache + heatmap_version) → hitung enforcement tiap 1 menit
8. getWeatherInfo(posisi user) + getWeatherArea
9. getRecommendation(for_date) → tampilkan marker rekomendasi

MODE BERLAYAR (offline di HP)
10. pilih rekomendasi → "Mulai Berlayar ke sini" → simpan target lokal
11. tracking GPS lokal, deteksi berhenti / auto-flag radius / peringatan zona (bagian 9)
12. "Selesai Berlayar" → isi BBM & tangkapan → postTrip(sailing, client_trip_id, track, fishing_points)
    (jika offline: antre di lokal, kirim ulang otomatis saat sinyal kembali)
13. tampilkan RecommendationSet baru

RIWAYAT
14. getHistoryTrip → klik → getTripDetail

LATAR BELAKANG
15. push zone_changed / getHeatmapVersion berubah → getHeatmapChanges → validasi rekomendasi lokal
16. setiap request membawa X-Heatmap-Version

LOGOUT
17. unregisterDevice → hapus token & cache lokal
```

---

## 13. Skema Database (Supabase / PostgreSQL + PostGIS)

```sql
create extension if not exists postgis;

create type user_role   as enum ('fisher', 'admin');
create type zone_status as enum ('normal', 'restricted', 'rehab');
create type trip_source as enum ('onboarding', 'manual', 'sailing');
create type rec_type    as enum ('fuel_saving', 'catch_max', 'balanced', 'habitual');
create type fatigue_lvl as enum ('healthy', 'tired', 'critical');

create table users (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text unique not null,              -- +62...
  password_hash text not null,             -- bcrypt
  role user_role not null default 'fisher',
  onboarded boolean not null default false,
  last_heatmap_version bigint,             -- dari header X-Heatmap-Version (12.B.10)
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

-- siap banyak kapal; MVP dibatasi 1 kapal per user oleh BE (12.B.0)
create table boats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text,
  engine_hp numeric not null check (engine_hp between 1 and 500),
  boat_length_m numeric not null check (boat_length_m between 2 and 30),
  fuel_type text not null default 'solar' check (fuel_type in ('solar','bensin')),
  home_port geography(Point, 4326) not null,
  is_default boolean not null default false,
  deleted_at timestamptz,                  -- soft delete (fase 2)
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index on boats (user_id);
-- satu kapal default aktif per user
create unique index boats_one_default on boats (user_id) where is_default and deleted_at is null;

-- 144.400 baris (380 x 380)
create table grids (
  id text primary key,                     -- 'a{a}b{b}'
  a smallint not null check (a between 1 and 380),
  b smallint not null check (b between 1 and 380),
  geom geometry(Polygon, 4326) not null,
  centroid geometry(Point, 4326) not null,
  is_sea boolean not null default true,
  has_coral boolean not null default false,
  coral_cover_pct numeric,
  coral_sensitivity numeric not null default 0.5,
  unique (a, b)
);
create index on grids using gist (geom);

create table zones (
  id uuid primary key default gen_random_uuid(),
  name text not null,                      -- unik hanya di antara zona aktif (partial index)
  status zone_status not null check (status <> 'normal'),
  max_catch_kg_per_period numeric,
  max_trips_per_period int,
  period text check (period in ('weekly','monthly')),
  open_schedule jsonb,                     -- {"days":[1,3,5],"hours":["05:00","12:00"]}
  effective_from timestamptz,
  effective_until timestamptz,
  reason text,
  note text,
  is_active boolean not null default true,
  archived_at timestamptz,                 -- diisi saat status diubah ke normal
  version int not null default 1,          -- optimistic locking (= ZoneEntry.zone_version)
  outline geometry(MultiPolygon, 4326),    -- ST_Union grid anggota, dihitung saat zona berubah
  bbox numeric[4],                         -- [minLng, minLat, maxLng, maxLat]
  changed_in_heatmap_version bigint,       -- versi saat zona terakhir berubah
  created_by uuid references users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- nama unik hanya di antara zona aktif
create unique index zones_name_active_uq on zones (lower(name)) where is_active;

-- satu grid maksimal satu zona
create table zone_grids (
  grid_id text primary key references grids(id),
  zone_id uuid not null references zones(id) on delete cascade,
  added_at timestamptz default now()
);
create index on zone_grids (zone_id);

create table zone_history (
  id bigserial primary key,
  zone_id uuid references zones(id),
  action text not null,                    -- create|update_meta|update_rules|add_grids|remove_grids|update_status|archive
  before jsonb, after jsonb,
  reason text,
  changed_by uuid references users(id),
  changed_at timestamptz default now()
);

create table grid_stats (
  grid_id text primary key references grids(id),
  trip_count_7d int default 0,
  trip_count_30d int default 0,
  fishing_hours_30d numeric default 0,
  catch_kg_30d numeric default 0,
  cpue_30d numeric,
  cpue_30d_smooth numeric,
  pressure_index numeric default 0,
  fatigue_index numeric default 0,
  fatigue_level fatigue_lvl default 'healthy',
  fatigue_updated_at timestamptz,
  days_low_fatigue int default 0,          -- untuk saran reopen
  auto_flag text check (auto_flag in ('restricted')),
  auto_flagged_at timestamptz,
  flag_dismissed_until timestamptz,
  suggestion text check (suggestion in ('reopen')),   -- saran buka kembali untuk grid di zona rehab
  last_visited_at timestamptz,
  updated_at timestamptz default now()
);

-- beban harian per grid (input rumus fatigue)
create table grid_daily_load (
  grid_id text references grids(id),
  day date not null,
  visits int default 0,
  fishing_hours numeric default 0,
  catch_kg numeric default 0,
  primary key (grid_id, day)
);

-- kuota zona per periode
create table zone_quota_usage (
  zone_id uuid references zones(id) on delete cascade,
  period_start date not null,
  used_kg numeric default 0,
  used_trips int default 0,
  primary key (zone_id, period_start)
);

create table trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  client_trip_id uuid not null,            -- idempotency key buatan HP
  source trip_source not null,
  boat_id uuid not null references boats(id),
  engine_hp_snapshot numeric not null,     -- snapshot spesifikasi kapal saat trip
  boat_length_m_snapshot numeric not null,
  departure geography(Point, 4326) not null,
  return_point geography(Point, 4326),
  departed_at timestamptz not null,
  returned_at timestamptz not null,
  fuel_liters numeric not null,
  catch_kg numeric not null,
  distance_from_port_km numeric,           -- dermaga → titik tangkap pertama
  total_distance_km numeric,
  duration_h numeric,
  fishing_hours numeric,
  fuel_per_km numeric,
  catch_per_liter numeric,
  fuel_efficiency_pct numeric,             -- terhadap baseline sebelum trip ini
  zone_violation boolean default false,
  selected_recommendation_id uuid,         -- FK ditambahkan setelah tabel recommendations
  notes text,
  created_at timestamptz default now(),
  unique (user_id, client_trip_id)
);
create index on trips (user_id, departed_at desc);
-- maksimal satu trip onboarding per user
create unique index trips_one_onboarding on trips (user_id) where source = 'onboarding';

create table trip_points (
  trip_id uuid references trips(id) on delete cascade,
  seq int not null,                        -- TrackPoint.seq dari HP
  location geography(Point, 4326) not null,
  recorded_at timestamptz not null,
  speed_ms numeric,
  accuracy_m numeric,
  primary key (trip_id, seq)
);

create table fishing_points (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid references trips(id) on delete cascade,
  location geography(Point, 4326) not null,
  grid_id text references grids(id),
  started_at timestamptz,
  ended_at timestamptz,
  zone_id_at_time uuid references zones(id),
  zone_status_at_time zone_status,
  fishing_hours numeric,
  reported_catch_kg numeric,               -- opsional, diisi nelayan per titik
  allocated_catch_kg numeric,              -- hasil pembagian catch_kg trip
  flag_source text check (flag_source in ('manual','user_confirmed','auto_timeout','rec_radius')),
  recommendation_id uuid references recommendations(id)   -- diisi jika flag_source = rec_radius
);

create table recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  trip_id uuid references trips(id),      -- trip pemicu (null jika dari getRecommendation)
  boat_id uuid references boats(id),
  type rec_type not null,
  grid_id text references grids(id),
  point geography(Point, 4326),
  predicted_fuel_liters numeric,
  fuel_efficiency_pct numeric,
  predicted_catch_kg numeric,
  predicted_catch_min numeric,
  predicted_catch_max numeric,
  departure_time time,
  return_time time,
  for_date date,
  confidence numeric,
  reason text,
  reason_codes text[],
  model_version text,
  is_fallback boolean not null default false,
  generated_at timestamptz not null default now(),
  valid_until timestamptz not null,
  created_at timestamptz default now()
);
create index on recommendations (user_id, for_date, generated_at desc);

alter table trips add constraint trips_selected_rec_fk
  foreign key (selected_recommendation_id) references recommendations(id);

create table weather_cache (
  cell_key text,                           -- sel sampel, mis. per 10x10 grid
  forecast_time timestamptz,
  lat numeric, lng numeric,
  wind_speed_ms numeric, wind_dir_deg numeric,
  wave_height_m numeric, temp_c numeric, weather_code int,
  fetched_at timestamptz default now(),
  primary key (cell_key, forecast_time)
);

-- riwayat dismiss auto-flag oleh admin
create table flag_dismissals (
  id bigserial primary key,
  grid_id text not null references grids(id),
  dismissed_until timestamptz not null,
  reason text not null,
  dismissed_by uuid references users(id),
  created_at timestamptz default now()
);
create index on flag_dismissals (grid_id, dismissed_until);

-- heatmap materialized: satu sumber untuk admin & nelayan (12.A.4)
create table heatmap_cells (
  grid_id text primary key references grids(id),
  fatigue numeric, fatigue_level fatigue_lvl,
  pressure_7d numeric, pressure_30d numeric,
  cpue_7d numeric, cpue_30d numeric,
  fatigue_smooth numeric, pressure_30d_smooth numeric, cpue_30d_smooth numeric,
  has_coral boolean not null,
  zone_id uuid references zones(id),
  auto_flag text,
  auto_flagged_at timestamptz,
  flag_dismissed_until timestamptz,
  -- statistik detail (dipakai getGridDetail & ZoneAggregate, tidak dikirim di getHeatmap)
  pressure_index numeric,
  trip_count_7d int, trip_count_30d int,
  fishing_hours_30d numeric, catch_kg_30d numeric,
  last_visited_at timestamptz,
  has_data boolean not null default false,
  is_relevant boolean generated always as (has_data or zone_id is not null or auto_flag is not null) stored,
  updated_version bigint not null          -- versi terakhir sel ini berubah
);
create index on heatmap_cells (updated_version);
create index on heatmap_cells (grid_id) where is_relevant;   -- aturan sel yang dikirim (12.A.2)
-- grid_stats = tabel kerja worker; heatmap_cells = snapshot yang dipublish ke kedua role

create sequence heatmap_version_seq;

create table heatmap_versions (
  version bigint primary key,
  trigger text not null,                   -- create_zone|edit_zone|edit_grids|edit_status|auto_flag|dismiss_flag|trip|daily|manual
  changed_cells int not null,
  changed_zone_ids uuid[],                 -- sumber zones_upserted di getHeatmapChanges
  removed_zone_ids uuid[],                 -- sumber zones_removed
  created_by uuid references users(id),
  reason text,
  created_at timestamptz default now()
);

create table heatmap_refresh_jobs (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('all','grids','zone')),
  params jsonb,
  status text not null default 'queued' check (status in ('queued','running','done','failed')),
  progress_pct int default 0,
  result_version bigint, changed_cells int, error text,
  requested_by uuid references users(id),
  started_at timestamptz, finished_at timestamptz,
  created_at timestamptz default now()
);
-- hanya satu refresh 'all' aktif sekaligus
create unique index one_full_refresh_running on heatmap_refresh_jobs ((true))
  where scope = 'all' and status in ('queued','running');

-- perangkat untuk push FCM (12.B.10)
create table user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android',
  app_version text,
  last_used_at timestamptz default now(),
  created_at timestamptz default now()
);
create index on user_devices (user_id);

-- antrean push, diproses worker
create table push_outbox (
  id bigserial primary key,
  zone_id uuid references zones(id),
  change text not null check (change in ('created','status_changed','grids_added','rules_changed','quota_exhausted','dissolved')),
  heatmap_version bigint not null,
  recipient_count int,
  status text not null default 'queued' check (status in ('queued','sent','failed')),
  attempts int not null default 0,
  created_at timestamptz default now(),
  sent_at timestamptz
);
create index on push_outbox (status, created_at);

create table app_config (
  key text primary key,                    -- mis. 'fatigue.alpha_base', 'sailing.stop_threshold_m'
  value jsonb not null,
  updated_at timestamptz default now()
);

-- agregat zona (6.4)
create view zone_aggregates as
select z.id as zone_id,
       count(g.id)                                       as grid_count,
       count(g.id) * 0.25                                as area_km2,
       count(*) filter (where g.has_coral)               as coral_grid_count,
       avg(s.fatigue)                                    as fatigue_avg,
       max(s.fatigue)                                    as fatigue_max,
       count(*) filter (where s.fatigue_level='healthy') as healthy_count,
       count(*) filter (where s.fatigue_level='tired')   as tired_count,
       count(*) filter (where s.fatigue_level='critical')as critical_count,
       sum(s.catch_kg_30d)                               as catch_kg_30d,
       sum(s.fishing_hours_30d)                          as fishing_hours_30d,
       sum(s.catch_kg_30d) / nullif(sum(s.fishing_hours_30d),0) as cpue_30d
from zones z
join zone_grids zg on zg.zone_id = z.id
join grids g on g.id = zg.grid_id
left join heatmap_cells s on s.grid_id = g.id      -- snapshot yang sama dengan heatmap
where z.is_active
group by z.id;
-- trip_count_30d & violation_count_30d dihitung terpisah dari fishing_points (distinct trip)

-- data training ML (tanpa data pribadi)
create view ml_training_trips as
select t.id, t.user_id, t.boat_id,
       t.engine_hp_snapshot as engine_hp, t.boat_length_m_snapshot as boat_length_m,
       t.fuel_liters, t.catch_kg, t.distance_from_port_km, t.total_distance_km,
       t.duration_h, t.fishing_hours, t.departed_at,
       fp.grid_id, fp.fishing_hours as point_fishing_hours, fp.allocated_catch_kg, fp.flag_source
from trips t
join fishing_points fp on fp.trip_id = t.id;
```

**Seeder:**
- Admin dari env `ADMIN_SEED_PHONE`, `ADMIN_SEED_PASSWORD`.
- Generate 144.400 grid dari `origin_x`, `origin_y` (env/konfigurasi) dengan rumus 5.1, `is_sea` dari data garis pantai (mis. OSM land polygons).
- `has_coral` dari dataset sebaran karang (lihat Open Questions) atau default `false`.
- `app_config` dengan parameter default, termasuk `flag.threshold_on` (0.7), `flag.threshold_off` (0.5), `flag.dismiss_default_days` (30), `flag.dismiss_max_days` (180), `heatmap.changes_max_versions` (50), `heatmap.changes_max_age_days` (7), `rec.valid_hours` (6), `rec.max_range_km` (40), `push.coalesce_minutes` (10), `push.recent_fishing_days` (30), `sync.active_days` (7), dan semua nilai `sailing.*` di `getMobileConfig` (12.B.9).

---

## 14. Pemanfaatan Data (Data Flow)

```
Trip nelayan ─▶ fishing_points (grid_id, allocated_catch_kg) ─▶ grid_daily_load
                                                                    │
                                                         worker harian / per trip
                                                                    ▼
                                         grid_stats (pressure, cpue, FATIGUE, suggestion)
                       ┌───────────────────────────┬───────────────┴──────────────┬──────────────────────┐
                       ▼                           ▼                              ▼                      ▼
         heatmap_cells (admin = nelayan)  heatmap_version / delta        Auto-flag & reopen       Kandidat & fitur ML
                       │                                                          │                      │
                       └──── admin pilih grid → buat/kelola ZONA ◀────────────────┘                      │
                                                   │                                                     │
                                       zones + zone_grids ─────────▶ filter kandidat ◀───────────────────┘
                                                                            ▼
                                                                Rekomendasi ke nelayan
                                                                            ▼
                                                           Nelayan berlayar ─▶ trip baru (loop)
```

| Data | Dimanfaatkan untuk |
|---|---|
| Trip (BBM, jarak, cuaca) | Model BBM, baseline efisiensi per nelayan |
| Titik tangkap + kg + durasi | Beban harian grid → fatigue, CPUE, model tangkapan, heatmap |
| Fatigue index | Heatmap, saran admin, penalti rekomendasi, mekanisme rotasi |
| Zona & kuota | Filter kandidat, peringatan peta, statistik kepatuhan |
| `zone_violation` | Laporan admin (untuk edukasi, bukan penalti otomatis) |
| Rekomendasi vs trip aktual | Evaluasi akurasi model & tingkat kepatuhan rekomendasi |

**Worker berkala (Go):**
| Jadwal | Tugas |
|---|---|
| Setelah trip selesai | Update `grid_daily_load`, `zone_quota_usage`, statistik grid terdampak |
| Tiap 1 jam | Refresh `weather_cache` untuk sel sampel pilot |
| Harian 00:10 WIB | Hitung fatigue semua grid, smoothing, saran, reset kuota sesuai periode, cek `effective_until`, lalu publish ke `heatmap_cells` |
| Tiap 10 detik | Kirim antrean `push_outbox` ke FCM (dengan penggabungan 10 menit) |

---

## 15. Cuaca
- Sumber: **Open-Meteo** (Forecast API untuk angin & suhu, Marine API untuk tinggi gelombang), gratis tanpa API key. Alternatif: BMKG.
- Diambil per **sel sampel** (mis. tiap 10 × 10 grid = 5 km) agar hemat request; disimpan di `weather_cache`.
- Klien **tidak** memanggil API cuaca langsung.
- `risk`: `high` jika angin > 10 m/s atau gelombang > 2 m; `medium` jika angin > 7 m/s atau gelombang > 1.25 m; sisanya `low` (ambang di `app_config`).

---

## 16. Aturan per Agent

### 16.1 BE agent (Go Gin)
- Struktur: `cmd/api`, `cmd/worker`, `cmd/seed`, `internal/{auth,user,trip,grid,zone,fatigue,recommendation,weather,mapdata}/`, `pkg/gridindex` (rumus 5.1 + unit test).
- Lapisan: handler → service → repository.
- `pkg/gridindex` adalah **implementasi referensi**: sediakan test vector (koordinat → ID) untuk dicocokkan Flutter, Next.js, dan ML.
- `pkg/zonerule` (evaluasi zona 12.A.2) juga implementasi referensi dengan test vector (zona + waktu WIB → `enforcement`), termasuk kasus pergantian hari, batas jam buka, dan `period_end` kuota.
- Semua endpoint yang menampilkan angka per grid / agregat zona membaca `heatmap_cells`, bukan `grid_stats`.
- Push FCM lewat `push_outbox` + worker; aksi zona tidak menunggu FCM.
- Safety net: sebelum mengirim rekomendasi, cek ulang tidak ada grid zona `rehab` / `critical`.
- Operasi zona (create, add/remove grid) dalam **satu transaksi** + tulis `zone_history`.
- Fallback heuristik jika ML timeout. Rate limit `/auth/*`.

### 16.2 Mobile agent (Flutter — nelayan saja)
- State management: Riverpod atau Bloc (pilih satu, konsisten).
- Struktur: `features/{auth,onboarding,boat,map,sailing,trip,recommendation,history,weather}`.
- Navigasi setelah login/buka aplikasi mengikuti `me.next_step` (`boat` → `first_trip` → `done`).
- Trip selesai disimpan ke *outbox* lokal dan dikirim via `postTrip` dengan `client_trip_id`; trip lama yang tertunda dikirim dengan `with_recommendations=false`.
- Implementasi rumus grid harus lolos test vector dari BE.
- Mode berlayar: foreground service, penyimpanan lokal, sync batch, deteksi berhenti & peringatan zona lokal.
- UI ramah nelayan: tombol besar, kontras tinggi (dipakai di bawah matahari), teks singkat, ikon jelas.
- Implementasi `zonerule` harus lolos test vector BE; `enforcement` dihitung ulang tiap 1 menit, tidak disimpan.
- FCM: `registerDevice` setelah login & saat token berubah, `unregisterDevice` saat logout; handler `zone_changed` memicu `getHeatmapChanges`. Header `X-Heatmap-Version` di semua request (interceptor HTTP).
- Heatmap memakai skala warna, ambang, dan data yang **sama** dengan Next.js. Simpan cache heatmap + `heatmap_version` di lokal, sinkron via `/map/heatmap/changes` (aturan di bagian 12.A.4).

### 16.3 Web agent (Next.js — admin saja)
- App Router + TypeScript. Peta: MapLibre GL JS + deck.gl.
- Struktur halaman: `/login`, `/map` (heatmap + seleksi + buat zona), `/zones`, `/zones/[id]`, `/suggestions`, `/stats`.
- Implementasi rumus grid harus lolos test vector dari BE; seleksi rectangle dihitung dari rentang indeks `a`/`b`.
- Preview agregat memanggil `/admin/zones/preview` dengan debounce saat seleksi berubah.
- Implementasi `zonerule` (TypeScript) harus lolos test vector BE; warna zona dari `enforcement`, dihitung ulang tiap 1 menit.
- Detail zona menampilkan `entry` (tampilan nelayan) dan `sync.known_by_pct`.
- JWT di cookie httpOnly; proteksi route via middleware.
- Optimal untuk layar desktop/laptop.

### 16.4 ML agent (Python)
- Ikuti kontrak bagian 11; jangan ubah field tanpa update dokumen ini.
- Notebook evaluasi (MAE BBM, MAE tangkapan) + versi model.
- Tidak mengakses data pribadi; tidak menghitung fatigue (sudah dari BE).

---

## 17. Milestone

| Fase | Isi |
|---|---|
| M1 | Auth, seeder admin & 144.400 grid, `pkg/gridindex` + test vector, endpoint grid-meta & sea-mask |
| M2 | Next.js: heatmap dummy, multi-select, buat & kelola zona, agregat zona, audit log |
| M3 | Flutter: register/login, onboarding, input trip manual, riwayat, peta zona |
| M4 | Worker: statistik grid, fatigue, saran; cuaca; rekomendasi heuristik 4 tipe |
| M5 | Flutter: mode berlayar (tracking, deteksi berhenti, offline sync, peringatan zona) |
| M6 | ML service v1 menggantikan heuristik, statistik admin |

---

## 18. Open Questions

1. **Lokasi pilot** — titik origin kiri bawah (`origin_x`, `origin_y`) untuk area 190 × 190 km di mana?
2. **Sumber data sebaran karang** (`has_coral`, `coral_cover_pct`) — dataset (mis. Allen Coral Atlas) atau input manual admin per grid/zona?
3. **Parameter fatigue** (α, half-life pemulihan, ambang level) — perlu divalidasi pihak konservasi.
4. **Kuota zona terbatas** — total untuk semua nelayan, atau per nelayan?
5. **Rehab kedaluwarsa** (`effective_until` lewat) — otomatis kembali `normal`, atau menunggu konfirmasi admin (dengan saran `reopen`)?
6. **Pembagian tangkapan multi-titik** — proporsional durasi (default) atau nelayan mengisi kg per titik?
7. **Dermaga** — perlu daftar dermaga resmi, atau titik berangkat bebas?

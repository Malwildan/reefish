# AGENTS.md — Sistem Rekomendasi Penangkapan Ikan Ramah Terumbu Karang

> Dokumen ini adalah **referensi produk & domain** untuk tim/agent **ML**, **Backend (BE)**, **Mobile (Flutter — nelayan)**, dan **Web (Next.js — konservatif)**.
> Kontrak API yang mengikat ada di `contracts/` (OpenAPI + markdown). Jika dokumen ini berbeda dengan `contracts/` atau kode, **`contracts/` yang berlaku**; perbarui dokumen ini sesudahnya.

**Versi dokumen:** 0.9 (16-10-2026) — disesuaikan dengan backend yang sudah dibangun:
- Arsitektur **Supabase-first + service Go untuk komputasi** (bagian 1), bukan semua API di Go.
- Auth **Supabase bawaan**: no. telp + password + **OTP SMS (Twilio)**; role `nelayan` / `konservatif` (bagian 3).
- Grid memakai grid data asli **187 × 177 sel** (EPSG:32749, origin 637500/8988000), ID `X{xxx}_Y{yyy}` + ID kanonis `tp-id-utm49s-500m:v2:rp{row}:cp{col}` (bagian 5.1).
- **Keputusan tim:** grid punya **3 status** lewat zona — `normal`, `restricted` (kuota tangkap **per zona**), `rehab` (zero tolerance, grid di-*disable*). Sistem hanya menandai sampai `restricted` (auto-flag); keputusan di pengelolaan zona oleh konservatif. Lock grid (dari branch main) kini hanya cerminan `rehab` (bagian 6).
- Endpoint = RPC Supabase `api_*` + Go `/api/v1/*` (bagian 12); skema = migrasi `backend/supabase/migrations/` (bagian 13); worker = SQL + `pg_cron` (bagian 14).

Riwayat sebelumnya: 0.8 pembagian Supabase vs Go, `ZoneEntry`, snapshot `heatmap_cells`, push & cakupan sinkron · 0.7 kontrak nelayan 12.B, satu `postTrip` idempoten · 0.6 auto-flag radius rekomendasi di mode berlayar · 0.5 kontrak admin 12.A · 0.4 heatmap satu sumber + delta · 0.3 zona = kumpulan grid, auto-flag `restricted` · 0.2 admin di Next.js, indeks kelelahan, grid 500 m, zona multi-select.

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
4. **Keputusan status zona tetap di tangan konservatif.** Sistem hanya memberi *saran*: menandai grid sampai `restricted` (auto-flag) atau zona rehab siap dibuka (`reopen`); grid hanya di-*disable* lewat zona `rehab`.

---

## 1. Arsitektur

```
┌──────────────────┐   supabase-js / supabase_flutter (RPC api_*, Auth)   ┌───────────────────────────────┐
│ Flutter (mobile) │ ───────────────────────────────────────────────────▶ │ Supabase (upyahsecuorqghcghflg)│
│ Nelayan          │                                                      │  Auth: phone + password + OTP │
└──────────────────┘                                                      │  Postgres + PostGIS + RLS     │
┌──────────────────┐                                                      │  RPC api_* (PostgREST)        │
│ Next.js (web)    │ ───────────────────────────────────────────────────▶ │  pg_cron: heatmap-daily       │
│ Konservatif      │                                                      └──────────────▲────────────────┘
└────────┬─────────┘                                                                     │ RPC dengan JWT user
         │ HTTPS + Bearer JWT Supabase                                                    │
         └──────────────▶ ┌────────────────────────┐ ────────────────────────────────────┘
   (mobile juga)          │ Go Gin (backend/api)   │ ──▶ Open-Meteo (forecast + marine)
                          │ rute, rekomendasi, cuaca│
                          └────────────────────────┘     ML service (FastAPI) — belum ada
```

| Komponen | Teknologi | Pengguna | Tanggung jawab |
|---|---|---|---|
| Mobile | Flutter | Nelayan | Auth, onboarding, peta, rekomendasi, mode berlayar, input trip, riwayat, buffer offline |
| Web | Next.js | Konservatif | Heatmap per grid, multi-select grid, manajemen zona, saran, statistik |
| Supabase | Postgres + PostGIS, Auth, RLS, PostgREST RPC, pg_cron | — | Semua data & aturan bisnis yang bisa di DB: profil, kapal, trip, zona, heatmap/fatigue, flag, statistik, sinkron |
| Go | Gin, `backend/api` | — | Komputasi: rute + BBM (`/v1/routes`), ranking rekomendasi + prediksi BBM, cuaca titik & area |
| ML | Python (FastAPI) | — | **Belum dibangun**; rekomendasi memakai heuristik Go (`is_fallback: true`) |

### 1.1 Aturan pembagian: Supabase-first, Go untuk komputasi

**Prinsip:** apa pun yang bisa dikerjakan Supabase (data, validasi, transaksi, RLS, agregasi SQL, jadwal) tetap di Supabase. Go hanya untuk komputasi yang tidak cocok di SQL atau yang butuh API eksternal.

| Area | Di mana | Catatan |
|---|---|---|
| Auth (register, login, OTP) | Supabase Auth | Dipanggil langsung oleh app (`signUp`, `verifyOTP`, `signInWithPassword` dengan phone) |
| Profil, kapal, trip, riwayat, config mobile | RPC Supabase | `api_me`, `api_create_boat`, `api_update_boat`, `api_post_trip`, `api_list_trips`, `api_trip_detail`, `api_mobile_config` |
| Peta, heatmap, zona, sinkron, perangkat | RPC Supabase | `api_grid_meta`, `api_sea_mask`, `api_zones`, `api_heatmap*`, `api_sync_seen`, `api_*_device` |
| Admin (zona, flag, saran, statistik) | RPC Supabase | `api_admin_*`, dicek role `konservatif` di dalam fungsi |
| Fatigue, pressure, CPUE, auto-flag, publish heatmap | SQL + `pg_cron` | Dihitung setiap trip selesai + harian 00:10 WIB |
| Ranking rekomendasi, prediksi BBM, jendela berangkat | Go | Data dari RPC `api_rec_context`, disimpan lewat `api_save_recommendations` |
| Cuaca titik & area | Go | Open-Meteo + cache memori 30 menit per sel ~1 km (`openmeteo.Cached`) |
| Rute pergi-pulang + BBM | Go | `docs/spesifikasi-backend-rute-nelayan-golang-gin.md` |
| Push FCM | Supabase (`push_outbox`) + Edge Function `push-dispatch` | Kode siap; aktif setelah secret `FCM_SERVICE_ACCOUNT` + jadwal `pg_cron` (belum ada akun Firebase) |

**Keamanan:** semua tabel RLS aktif. Klien hanya membaca/menulis lewat RPC `security definer` yang memeriksa `auth.uid()` dan role. Go memanggil Supabase dengan JWT user (bukan service role), jadi RLS tetap berlaku.

---

## 2. Konvensi Global (WAJIB)

| Hal | Konvensi |
|---|---|
| Koordinat geografis | WGS84 / **EPSG:4326**. GeoJSON `[lng, lat]`; objek JSON biasa `{ "lat": ..., "lng": ... }` |
| Proyeksi grid | **UTM zona 49S (EPSG:32749)** — semua perhitungan grid dalam meter di proyeksi ini |
| Ukuran grid | **500 m × 500 m** |
| Area pilot | bbox `[112.25, -9.15, 113.10, -8.35]`; indeks **187 kolom × 177 baris**, **31.354 sel** punya data |
| ID grid | **`X{grid_x:03}_Y{grid_y:03}`**, contoh `X149_Y001`; ID kanonis `tp-id-utm49s-500m:v2:rp{row}:cp{col}` untuk sel yang sama (bagian 5.1). **Bukan koordinat** |
| Waktu | Disimpan **UTC** (`timestamptz`), dikirim ISO-8601. UI menampilkan **WIB (Asia/Jakarta)** |
| Jam rekomendasi | `HH:mm` WIB + `for_date` |
| BBM | Liter (`fuel_liters`). Istilah UI: **"Solar/BBM"** |
| Berat ikan | Kilogram (`catch_kg`) |
| Jarak | Kilometer (`*_distance_km`, mis. `distance_from_port_km`) |
| Angin | Kecepatan m/s; arah derajat 0–360 (arah **asal** angin) + label `U, TL, T, TG, S, BD, B, BL` |
| Skor/indeks | Selalu dinormalisasi **0–1** |
| JSON | `snake_case` |
| Error | RPC Supabase: HTTP 400 `{ "code": "P0001", "message": "<KODE>", "hint": "<pesan>", "details": "<json>" }`. Go: `{ "error": { "code", "message", "details"? } }` |
| ID entitas | UUID v4 (kecuali grid) |
| Bahasa UI | Bahasa Indonesia |

---

## 3. Role & RBAC

| Role | Cara dibuat | Klien | Akses |
|---|---|---|---|
| `nelayan` | Daftar sendiri: no. telp + password + OTP SMS | Flutter | Data milik sendiri, peta & heatmap (sama dengan konservatif), rekomendasi |
| `konservatif` | Akun dipromosikan manual (`update profiles set role = 'konservatif'`) | Next.js | Data agregat grid/zona, manajemen zona, saran, statistik |

**Aturan:**
- Auth = **Supabase Auth bawaan** (branch main): `signUp(phone, password)` → `verifyOTP` (SMS Twilio) → `signInWithPassword`. JWT Supabase (default 1 jam + refresh token).
- `profiles.role` default `nelayan`; role tidak pernah diambil dari metadata signup. `profiles.phone` = `auth.users.phone` (E.164 tanpa `+`).
- Pemeriksaan role ada di dalam RPC (`private.require_nelayan`, `require_konservatif`, `require_member`). Endpoint bersama (peta, heatmap, `api_me`, cuaca) bisa dipakai kedua role.
- Nelayan tidak bisa melihat trip/lokasi nelayan lain secara individual (RLS select-own).
- Flutter menolak masuk jika `role = konservatif` (arahkan ke dashboard web); Next.js menolak `role = nelayan`.

---

## 4. Daftar Fitur

### 4.1 Nelayan (Flutter)
1. **Register** — `phone` (E.164), `password`, verifikasi **OTP SMS**. Password di-hash oleh Supabase Auth.
2. **Login** — `phone` + `password` → JWT Supabase.
3. **Onboarding** (wajib sekali): kapal diisi **sekali** + 1 trip baseline (`postTrip`, 12.B.4) berisi koordinat berangkat, titik tangkap, BBM (liter), tangkapan (kg), jam berangkat & pulang.
4. **Rekomendasi** (setelah onboarding & setiap trip selesai) — 4 tipe: `fuel_saving`, `catch_max`, `balanced`, `habitual`.
5. **Dashboard peta** — zona, grid (zoom dekat), heatmap kondisi area, titik rekomendasi, posisi user, cuaca.
6. **Cuaca** — kondisi cuaca, arah angin, kecepatan angin, suhu (+ tinggi gelombang).
7. **Catat trip** — manual (pasca berlayar) atau **Mode Berlayar** (real-time, polling 2 menit).
8. **Riwayat trip** — list + detail.

### 4.2 Admin (Next.js)
1. Login (akun yang sudah dipromosikan ke `konservatif`).
2. **Heatmap per grid** — metrik: kelelahan (fatigue), tekanan, CPUE.
3. **Multi-select grid → buat Zona** (nama + status + aturan).
4. **Kelola zona** — ubah status/aturan, tambah/kurangi grid, nonaktifkan zona.
5. **Detail zona** — data **agregat** semua grid di dalamnya.
6. **Detail grid** — statistik satu grid & zona tempat grid berada.
7. **Saran sistem** — grid yang disarankan dibatasi (auto-flag `restricted`) dan zona rehab yang siap dibuka (`reopen`): `api_admin_suggestions`.
8. **Audit log** perubahan zona.
9. **Statistik ringkas** — total trip, zona paling lelah, pelanggaran.

---

## 5. Model Domain: Grid

### 5.1 Sistem ID grid

Grid tetap: persegi 500 × 500 m di **WGS 84 / UTM 49S (EPSG:32749)**, sama dengan data ML, panduan peta Flutter, dan grid lock branch main. Kontrak lengkap + test vector: **`contracts/grid-index.md`** dan `contracts/fixtures/grid-index-vectors.json` (implementasi referensi: `backend/api/internal/domain/gridindex`).

```
(E, N)  = project_to_utm49s(lng, lat)
grid_x  = floor((E - 637500) / 500) + 1        // 1..187, timur
grid_y  = floor((N - 8988000) / 500) + 1       // 1..177, utara
ID      = X{grid_x:03}_Y{grid_y:03}            // grid_cells.grid_id, contoh X149_Y001
cell_id = tp-id-utm49s-500m:v2:rp{grid_y + 17975}:cp{grid_x + 1274}   // grid_cells.cell_id (kanonis main)
pusat   = (637500 + (grid_x - 0.5) * 500, 8988000 + (grid_y - 0.5) * 500) → unproject
```

- Tepi kiri/bawah inklusif. Indeks di dalam rentang tidak menjamin sel punya data; sel tanpa data = "tidak ada data", bukan nol dan bukan daratan.
- **Tetangga grid:** `(grid_x ± 1, grid_y ± 1)` — untuk smoothing dan seleksi kotak.
- Library proyeksi: PostGIS `ST_Transform`, Flutter `proj4dart`, Next.js `proj4`, Python `pyproj`, Go `gridindex` (Snyder TM). Semua harus lolos test vector.

### 5.2 Data per grid

| Kelompok | Field | Sumber |
|---|---|---|
| **Identitas** (statis) | `grid_id`, `cell_id`, `grid_x`, `grid_y`, `geom` (pusat), `cell` (polygon), `is_sea` | Import data ML (`backend/scripts/geojson_to_csv.py`) |
| **Habitat** | `has_coral` (dari `coral_areas`, kode 1), `coral_cover_pct`, `coral_sensitivity` (default 0.5) | `private.refresh_coral()` |
| **Statistik** (worker) | `trip_count_7d`, `trip_count_30d`, `fishing_hours_30d`, `catch_kg_30d`, `cpue_30d`, `pressure_index`, `last_visited_at` | Agregasi trip |
| **Kelelahan** (worker) | `fatigue_index`, `fatigue_level`, `fatigue_updated_at`, `days_since_last_load` | Rumus 5.3 |
| **Keanggotaan zona** | `zone_id` (nullable; maksimal **1 zona aktif** per grid) | Admin |
| **Saran** | `auto_flag = 'restricted'` (restrict), `suggestion = 'reopen'` | `private.auto_flag`, `daily_refresh` |

Grid tanpa zona = **normal** secara default.

### 5.3 Indeks Kelelahan (Fatigue Index)

Tujuan: mengukur seberapa "capek" area dari tekanan penangkapan, dengan memperhitungkan pemulihan alami.

Dihitung oleh SQL (`private.recompute_stats`) setiap trip selesai (grid tersentuh + tetangga) dan harian lewat `pg_cron` (`private.daily_refresh`, 00:10 WIB):

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

> Semua parameter di `app_config` (`fatigue`, `flag`), **bukan hardcode**, dan harus divalidasi dengan pihak konservasi.
> Implementasi saat ini memakai bentuk tertutup `Σ α·load_d·e^(−λ·Δt)` atas 180 hari dengan clamp di akhir (bukan per hari) — perkiraan yang disengaja.

**Level kelelahan:**

| Level | Rentang | Warna | Arti |
|---|---|---|---|
| `healthy` | < 0.4 | hijau | Aman dimanfaatkan |
| `tired` | 0.4 – 0.7 | kuning | Kurangi tekanan |
| `critical` | ≥ 0.7 | merah | Perlu diistirahatkan |

**Saran otomatis (tidak mengubah status):**
- **Auto-flag `restricted`** — grid tanpa zona dengan `fatigue_index ≥ 0.7` ditandai sistem; flag hilang saat `fatigue_index < 0.5` atau grid masuk zona. Hanya penanda tampilan, tidak membatasi nelayan. Detail: `api_internal_auto_flag` + `api_admin_list_flags` / `api_admin_dismiss_flags`.
- `reopen` — grid di zona rehab dengan `fatigue_index < 0.2` selama ≥ 30 hari berturut-turut.

Zona rehab tidak mendapat beban baru → fatigue turun alami → muncul saran `reopen`. Inilah mekanisme **rotasi**, bukan larangan permanen.

### 5.4 Smoothing statistik
Grid 500 m membuat data per grid jarang (sparse). Untuk heatmap & ML, sediakan juga nilai **smoothed** (rata-rata berbobot dengan 8 tetangga) di field `*_smooth`. Heatmap admin menampilkan nilai mentah secara default, dengan toggle "haluskan".

---

## 6. Model Domain: Zona

**Keputusan tim (16-10-2026): setiap grid punya satu dari 3 status.**

| Status grid | Dari mana | Arti | Kapasitas |
|---|---|---|---|
| `normal` | grid tidak masuk zona aktif | Bebas menangkap (dengan penalti fatigue di rekomendasi) | — |
| `restricted` | grid di zona `restricted` | Boleh menangkap dengan **kuota tangkap per zona** (kg dan/atau trip per minggu/bulan) + jadwal buka opsional | Dihitung bersama untuk semua grid di zona itu |
| `rehab` | grid di zona `rehab` | **Zero tolerance**, grid di-*disable*: tidak direkomendasikan, rute menghindar, pemilihan lokasi tangkap ditolak (`validate_fishing_grid_selection`), muncul di snapshot lock | — |

- **Sistem hanya menandai sampai `restricted`.** Auto-flag (fatigue ≥ 0.7) adalah saran, tidak membatasi nelayan.
- **Keputusan di tangan konservatif** lewat pengelolaan zona: grid ber-flag diagregasi menjadi zona, lalu status/kuota/masa berlaku diatur di zona (`api_admin_create_zone`, `api_admin_edit_zone*`).
- Zona = **sekumpulan grid** (`zone_grids`, satu grid maksimal satu zona aktif) yang dikelola sebagai satu unit kebijakan. Status zona hanya `restricted` atau `rehab`; mengubah status ke `normal` = **membubarkan zona** (diarsipkan, grid dilepas).
- **Lock grid branch main** (`get_grid_lock_snapshot`) kini hanya mencerminkan sel `rehab`; `set_grid_lock` dipensiunkan (`DEPRECATED_USE_ZONES`). Lihat `contracts/grid-locks.md`.
- Kontrak lengkap: `contracts/map-zones-api.openapi.yaml`. Admin juga bisa memilih grid dengan **polygon** (pusat sel di dalam polygon).

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
- Zona `restricted` yang kuotanya habis **tidak direkomendasikan** dan dihindari rute sampai periode berikutnya, tetapi **tidak** di-*disable* (status asli tidak berubah; bukan lock).
- Setiap perubahan (status, aturan, anggota grid) dicatat di audit log.

### 6.3 Status zona

| Status | Kode | Arti untuk nelayan | Boleh direkomendasikan? |
|---|---|---|---|
| Normal (tanpa zona) | — | Bebas menangkap | Ya (dengan penalti fatigue) |
| Terbatas | `restricted` | Boleh dengan kuota/jadwal | Ya, jika kuota tersisa & dalam jadwal |
| Rehab penuh | `rehab` | Dilarang total, grid di-*disable* | **Tidak pernah** |

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

### 7.1 Strategi data peta (31.354 sel ber-data)
- **Geometri grid TIDAK dikirim sebagai GeoJSON.** Klien membangun sel sendiri dari `api_grid_meta` (origin, ukuran sel, jumlah baris/kolom, EPSG) dengan rumus 5.1.
- **Mask sel ber-data** dikirim sekali sebagai bitset base64 (`api_sea_mask`, urutan y lalu x), di-cache dengan `version`.
- **Nilai layer dikirim sparse**: hanya grid yang punya nilai, format tuple + `columns`, semua metrik & kamus zona dalam satu payload (lihat bagian 12.A.4).
- Endpoint nilai menerima filter rentang indeks (`p_x_min..p_y_max`) **atau** `p_bbox`.
- Garis grid hanya digambar pada **zoom tinggi** (mis. zoom ≥ 13), karena di zoom jauh 500 m terlalu rapat.
- **Zona dikirim sebagai daftar grid ID per zona + outline gabungan** (outline dihitung BE dengan `ST_Union`, dikirim GeoJSON) agar ringan dirender.

### 7.2 Daftar layer

| # | Layer | Bentuk render | Nelayan (Flutter) | Admin (Next.js) | Endpoint |
|---|---|---|---|---|---|
| L0 | Basemap laut | Raster tile | ✅ | ✅ | OSM / ESRI Ocean |
| L1 | Garis grid 500 m | Garis (zoom ≥ 13) | ✅ | ✅ | `api_grid_meta` (dibangun klien) |
| L2 | Zona | Fill + outline per zona | ✅ | ✅ | `api_zones` |
| L3 | Heatmap kelelahan | Fill per grid | ✅ | ✅ | `api_heatmap` (kolom `fatigue`) |
| L4 | Heatmap tekanan | Fill per grid | ✅ | ✅ | `api_heatmap` (kolom `pressure`) |
| L5 | Heatmap CPUE | Fill per grid | ✅ | ✅ | `api_heatmap` (kolom `cpue`) |
| L6 | Auto-flag sistem | Outline oranye putus-putus | ✅ | ✅ | `api_heatmap` (kolom `auto_flag`) |
| L7 | Seleksi grid | Highlight biru | ❌ | ✅ | state lokal |
| L8 | Titik rekomendasi | Marker + garis dari dermaga | ✅ | ❌ | Go `/api/v1/recommendations` |
| L9 | Posisi & track berlayar | Marker + polyline | ✅ | ❌ | GPS lokal |
| L10 | Titik tangkap historis user | Marker kecil | ✅ | ❌ | `api_trip_detail` |
| L11 | Cuaca / panah angin | Ikon per sel sampel | ✅ | ✅ | Go `/api/v1/weather/area` |
| L12 | Layer ML per periode (potensi, suhu, klorofil, kedalaman, potensi ikan) | Fill per grid | ✅ (aset bawaan app) | ✅ | `api_layers(p_period)` |
| L13 | Habitat coral & mangrove | Polygon | ✅ (aset bawaan app) | ✅ | `api_habitat()` |

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
- **Peringatan zona dihitung di HP**: cache peta `grid_id → status` dari `api_zones` (dan sel rehab dari `get_grid_lock_snapshot`), hitung ID grid dari GPS (rumus 5.1) → lookup O(1).
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

### 10.5 Implementasi saat ini (heuristik Go, sebelum ML)
- Kandidat: sel `cluster_predictions` periode terbaru dengan `level ≥ 3`, ≤ 40 km dari dermaga, **bukan** zona `rehab`/kuota habis, **bukan** fatigue `critical` (`api_rec_context`).
- Skor = `wF·F + wC·C − 0.15·K − 0.05·P` dengan `F` jarak ternormalisasi, `C` potential_score ternormalisasi, `K` fatigue (×2 jika `tired`), `P` keramaian = jumlah rekomendasi ke sel itu di tanggal yang sama (pembagi 5, maks 1). `W` per sel belum ada (cuaca diambil satu titik di dermaga).
- Tiap tipe memilih sel yang belum dipakai tipe lain di set yang sama.
- `habitual` = sel yang paling sering dikunjungi; diganti sel terdekat yang diizinkan jika kini rehab/kuota habis/critical.
- BBM = `2 × jarak × fuel_per_km nelayan (atau default) × faktor cuaca`; tangkapan = `rata-rata tangkapan × (0.5 + C)`, rentang ±30 %.
- Jam berangkat = jam 03:00–08:00 WIB dengan risiko terburuk terendah selama trip (panjang trip dari config, 6,5 jam); fallback 04:30–11:00.
- Cache set dipakai ulang selama `valid_until` (6 jam) **dan** tidak ada sel di set yang berubah di peta sejak dibuat.
- Semua set ditandai `is_fallback: true`, `model_version: heuristic-0.1`.

---

## 11. Kontrak ML

> **Status:** ML service belum dibangun. Kontrak di bawah tetap acuan untuk tim ML; BE memakai heuristik bagian 10.5 sampai service ini tersedia.

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

## 12. API Backend

**Kontrak yang mengikat ada di `contracts/`:**

| File | Isi |
|---|---|
| `contracts/nelayan-api.openapi.yaml` | RPC nelayan (profil, kapal, trip, riwayat, config) + Go rekomendasi & cuaca |
| `contracts/map-zones-api.openapi.yaml` | Peta bersama, heatmap, sinkron, perangkat, semua RPC admin konservatif |
| `contracts/grid-locks.md` | Lock grid (cerminan `rehab`) dari branch main |
| `contracts/grid-index.md` | Rumus & test vector grid |
| `contracts/route-api.openapi.yaml` | Go `POST /v1/routes` (rute + BBM) |

**Cara panggil:**
- RPC Supabase: `POST {SUPABASE_URL}/rest/v1/rpc/<nama>` dengan `apikey` + `Authorization: Bearer <access_token>`, argumen bernama di body. Dari app: `supabase.rpc('<nama>', params: {...})`.
- Go: `https://<host>/api/v1/...` dengan `Authorization: Bearer <access_token Supabase>`; respons `{ data, request_id }`.
- Tidak ada ETag/304: klien membandingkan `heatmap_version` / `version`. `410` diganti kode `FULL_RELOAD_REQUIRED`. Header `X-Heatmap-Version` diganti RPC `api_sync_seen`.

### 12.A Admin (konservatif) — nama spec → implementasi

| Spec | Implementasi |
|---|---|
| login / me | Supabase Auth / `api_me` (bentuk admin: `next_step` `done`, `boat`/`stats` null) |
| getGridMeta, getSeaMask, getZones | `api_grid_meta`, `api_sea_mask`, `api_zones` |
| getHeatmap, getHeatmapVersion, getHeatmapChanges | `api_heatmap`, `api_heatmap_version`, `api_heatmap_changes` |
| getWeatherArea | Go `GET /api/v1/weather/area` |
| refreshHeatmap, getRefreshStatus | `api_admin_refresh_heatmap` (antre job, dijalankan `pg_cron` tiap 10 detik), `api_admin_refresh_status` |
| getGridDetail | `api_admin_grid_detail` |
| previewZona, createZona | `api_admin_preview_zone`, `api_admin_create_zone` (`grid_ids` atau `polygon`) |
| readListZona, readDetailZona | `api_admin_list_zones`, `api_admin_zone_detail` |
| editZona, editGridZona, editStatusZona | `api_admin_edit_zone`, `api_admin_edit_zone_grids`, `api_admin_edit_zone_status` |
| automaticFlagToRestricted | `api_internal_auto_flag` (service_role) + `pg_cron` |
| listFlags, dismissFlag | `api_admin_list_flags`, `api_admin_dismiss_flags` |
| Saran sistem (4.2 #7) | `api_admin_suggestions` (`restrict` + `reopen`) |
| zoneHistory, statsSummary | `api_admin_zone_history`, `api_admin_stats_summary` |

### 12.B Nelayan — nama spec → implementasi

| Spec | Implementasi |
|---|---|
| register, login | Supabase Auth (phone + password + OTP) |
| me | `api_me` |
| createBoat, updateBoat | `api_create_boat`, `api_update_boat` |
| postTrip | `api_post_trip` (idempoten `client_trip_id`; `replay: true`; `recommendations` = null → panggil Go) |
| getHistoryTrip, getTripDetail | `api_list_trips`, `api_trip_detail` |
| getRecommendation | Go `GET /api/v1/recommendations` |
| getConstraint, getHeatmap | sama dengan 12.A (`api_zones`, `api_heatmap*`) + `get_grid_lock_snapshot` untuk sel rehab |
| getWeatherInfo | Go `GET /api/v1/weather` (kedua role) |
| getMobileConfig | `api_mobile_config` (tanpa login) |
| registerDevice, unregisterDevice | `api_register_device`, `api_unregister_device` |
| X-Heatmap-Version | `api_sync_seen(p_heatmap_version)` |

### 12.C Aturan evaluasi zona di klien (12.A.2 lama, masih berlaku)

`ZoneEntry` (bentuk tunggal batasan zona, lihat `map-zones-api`) dievaluasi klien setiap 1 menit:

**Aturan evaluasi zona** — WAJIB identik di Flutter dan Next.js. Server memakai versi tanpa `open_schedule` (`private.zone_closed`).
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

Klien menghitung ulang `enforcement` **setiap 1 menit** dari data lokal, tanpa request. Server memakai versi tanpa `open_schedule` (`private.zone_closed`) pada jam berangkat untuk kandidat rekomendasi dan rute.

---

## 13. Skema Database (Supabase / PostgreSQL + PostGIS)

Sumber kebenaran = migrasi berurutan di `backend/supabase/migrations/`:

| Migrasi | Isi |
|---|---|
| `20261016000020` … `001628` (main) | Grid lock: `map_areas`, `grid_definitions`, `grid_restrictions`, `map_area_admins`, `reefish_private.*` |
| `20261016100000_schema` / `100100_rls` | `profiles` (role `nelayan`/`konservatif`), `cluster_levels`, `grid_cells`, `cluster_predictions`, RLS |
| `100200_rpc` / `100300_route_support` | `get_clusters`, `get_fishing_spots`, `grid_points` |
| `100400_phone_profile` | `profiles.phone` dari `auth.users.phone` |
| `100500_nelayan` | `boats`, `trips`, `trip_points`, `fishing_points`, `recommendation_sets`, `recommendations`, `app_config`, RPC nelayan |
| `100600_zones_heatmap` | kolom grid (`grid_x/y`, `cell`, `cell_id`, `is_sea`, `has_coral`…), `coral_areas`, `zones`, `zone_grids`, `zone_history`, `zone_quota_usage`, `grid_daily_load`, `grid_stats`, `heatmap_cells`, `heatmap_versions`, `heatmap_refresh_jobs`, `flag_dismissals`, `user_devices`, `push_outbox`, RPC peta & admin, `pg_cron` |
| `100700_ml_layers` | `grid_layers` (potensi ikan), `mangrove_areas`, `api_layers`, `api_habitat` |
| `100800_rec_penalties` | input penalti K/P, jendela berangkat, kesegaran cache rekomendasi |
| `100900_admin_reuse` | `api_me`/`api_in_pilot` untuk kedua role, `api_admin_suggestions` |
| `101000_rehab_lock` | lock grid = sel `rehab`; `set_grid_lock` dipensiunkan |
| `101100_push_dispatch` | `private.push_recipients`, `api_internal_push_claim` / `api_internal_push_done` (service_role), status `sending` |

**Prinsip yang dipertahankan dari 0.8:** satu zona aktif per grid (PK `zone_grids`), nama zona unik di antara zona aktif, satu kapal default per user, satu trip onboarding per user, idempotensi `(user_id, client_trip_id)`, satu refresh heatmap penuh sekaligus, `heatmap_cells` = satu snapshot untuk admin & nelayan.

**Data:** `grid_cells` + `cluster_predictions` + `coral_areas` + `mangrove_areas` + `grid_layers` diimport dari `machine-learning/data` (gitignored) lewat `backend/scripts/geojson_to_csv.py`; langkahnya di `backend/supabase/setup/README.md`. Data demo: `backend/supabase/seed/`.

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

**Pekerjaan terjadwal (SQL + pg_cron):**
| Jadwal | Tugas |
|---|---|
| Setelah trip (`private.after_trip`, di transaksi `api_post_trip`) | `grid_daily_load`, `zone_quota_usage`, statistik + auto-flag grid tersentuh & tetangga, publish heatmap |
| Harian 00:10 WIB (`pg_cron` `heatmap-daily` → `private.daily_refresh`) | Fatigue semua grid, smoothing, auto-flag, saran `reopen`, snapshot tren fatigue, rollover kuota, publish |
| Tiap menit (`pg_cron` → Edge Function `push-dispatch`, **belum dijadwalkan**: menunggu Firebase) | Kirim `push_outbox` ke FCM HTTP v1, retry 3×, hapus token mati |

---

## 15. Cuaca
- Sumber: **Open-Meteo** (Forecast API untuk angin, suhu, kode cuaca; Marine API untuk tinggi gelombang), dipanggil oleh **Go** (`backend/api/internal/adapter/openmeteo`). Klien tidak memanggil API cuaca langsung.
- Cache di memori proses Go: 30 menit, maks 512 entri, kunci = koordinat dibulatkan 0.01° + jam mulai. Error tidak di-cache. Cuaca area = satu request multi-lokasi 5 × 5 titik.
- Batas: cache per instance Cloud Run; pindah ke cache bersama jika instance banyak dan rate limit Open-Meteo terasa.
- `risk`: `high` jika angin > 10 m/s atau gelombang > 2 m; `medium` jika angin > 7 m/s atau gelombang > 1.25 m; `unknown` jika angin/gelombang kosong (null tidak pernah dianggap tenang); sisanya `low`.
- Gelombang dekat pantai bisa null dari Marine API; tetap null di respons.

---

## 16. Aturan per Agent

### 16.1 BE agent (Supabase + Go)
- Supabase-first (bagian 1.1). Perubahan skema = **migrasi baru** bertimestamp di `backend/supabase/migrations/` (jangan ubah migrasi yang mungkin sudah di hosted) + smoke test di `backend/supabase/tests/` (transaksi + rollback).
- RPC publik `security definer`, `search_path` tetap, cek role di dalam fungsi; error `private.fail(KODE, pesan, details)`.
- Go (`backend/api`, module `nelayan-route`): `adapter -> usecase -> domain`; domain tanpa Gin/HTTP/SQL. Go memanggil Supabase dengan JWT user.
- `gridindex` (Go) + `contracts/fixtures/grid-index-vectors.json` = implementasi referensi grid.
- Semua angka per grid / agregat zona membaca `heatmap_cells`, bukan `grid_stats`.
- Safety net rekomendasi: tidak pernah sel `rehab`, kuota habis, atau fatigue `critical`.
- CI: `.github/workflows/backend.yml` (gofmt, vet, test, `deno test` Edge Function, cek sintaks SQL). Deploy Go: `backend/api/Dockerfile` → Cloud Run (`backend/api/README.md`). Jangan pernah `supabase config push` (auth hosted diatur di dashboard).

### 16.2 Mobile agent (Flutter — nelayan saja)
- Auth: `SupabaseAuthRepository` (phone + password + OTP). Navigasi setelah login mengikuti `api_me.next_step` (`boat` → `first_trip` → `done`).
- Trip selesai disimpan ke *outbox* lokal lalu dikirim via `api_post_trip` dengan `client_trip_id`; setelah sukses panggil Go `/api/v1/recommendations`.
- Implementasi rumus grid harus lolos test vector `contracts/fixtures/grid-index-vectors.json`.
- Mode berlayar: foreground service, penyimpanan lokal, sync batch, deteksi berhenti & peringatan zona lokal; lokasi tangkap divalidasi `validate_fishing_grid_selection` (menolak sel rehab).
- `enforcement` zona dihitung ulang tiap 1 menit dari `ZoneEntry` (12.C), tidak disimpan.
- Push: `api_register_device` setelah login & saat token berubah, `api_unregister_device` saat logout. Setelah sinkron, panggil `api_sync_seen(heatmap_version)`.
- Heatmap: cache + `heatmap_version`, sinkron via `api_heatmap_changes`; skala & ambang sama dengan web. Layer ML/habitat saat ini dari aset bawaan app (keputusan sumber layer masih terbuka).
- UI ramah nelayan: tombol besar, kontras tinggi, teks singkat, ikon jelas.

### 16.3 Web agent (Next.js — konservatif saja)
- App Router + TypeScript. Peta: MapLibre GL JS + deck.gl.
- Halaman: `/login`, `/map` (heatmap + seleksi + buat zona), `/zones`, `/zones/[id]`, `/suggestions`, `/stats`.
- Seleksi grid: klik, kotak (rentang `grid_x`/`grid_y`), atau polygon (`polygon` di preview/create).
- Preview agregat memanggil `api_admin_preview_zone` dengan debounce.
- Warna zona dari `enforcement` (12.C), dihitung ulang tiap 1 menit.
- Detail zona menampilkan `entry` (tampilan nelayan) dan `sync.known_by_pct`.
- Sesi Supabase di cookie httpOnly (SSR helper); proteksi route via middleware.

### 16.4 ML agent (Python)
- Ikuti kontrak bagian 11; jangan ubah field tanpa update dokumen ini dan `contracts/`.
- Pengganti heuristik bagian 10.5: BE akan memanggil `/ml/v1/recommend` dengan kandidat dari `api_rec_context`.
- Notebook evaluasi (MAE BBM, MAE tangkapan) + versi model.
- Tidak mengakses data pribadi; tidak menghitung fatigue (sudah dari BE).

---

## 17. Milestone (status 16-10-2026)

| Fase | Isi | Status |
|---|---|---|
| M1 | Auth, grid + test vector, grid-meta & sea-mask | ✅ backend (auth OTP perlu Twilio aktif di hosted) |
| M2 | Next.js: heatmap, multi-select, kelola zona, agregat, audit log | ✅ API · ❌ web belum dibuat |
| M3 | Flutter: register/login, onboarding, input trip, riwayat, peta zona | ✅ API · 🟡 mobile: auth + peta (main), trip belum terhubung |
| M4 | Statistik grid, fatigue, saran; cuaca; rekomendasi heuristik 4 tipe | ✅ |
| M5 | Flutter: mode berlayar (tracking, deteksi berhenti, offline sync, peringatan zona) | ❌ |
| M6 | ML service v1 menggantikan heuristik | ❌ |
| — | Deploy hosted (migrasi gipar, import data, pg_cron) | ✅ s.d. `20261016125501` (lihat `docs/frontend/hackathon-integration.md`); 🟡 `20261016130000_refresh_async` belum di hosted |
| — | Deploy Go | ✅ Railway (`reefish-api-production.up.railway.app`); Render Blueprint `render.yaml` = alternatif |
| — | Pengirim FCM, OTP SMS hosted | 🟡 kode siap; menunggu akun Firebase dan Twilio |

---

## 18. Open Questions

**Sudah terjawab**
- ~~Lokasi pilot / origin grid~~ → origin 637500/8988000 EPSG:32749, bbox `[112.25, -9.15, 113.10, -8.35]` (bagian 5.1).
- ~~Sumber data karang~~ → `coralreef.geojson` (kode 1 dianggap karang, kamus kelas belum dikonfirmasi) → `has_coral`.
- ~~Model pembatasan~~ → 3 status grid lewat zona; kuota per zona; lock = rehab (bagian 6).

**Masih terbuka**
1. **Format ID grid di API** — tetap `X{xxx}_Y{yyy}` atau pindah ke ID kanonis `tp-id-…` (keduanya sudah tersedia).
2. **Identitas admin** — `profiles.role = 'konservatif'` (dipakai sekarang) atau `map_area_admins` (main).
3. **Sumber layer ML di mobile** — aset bawaan app (sekarang) atau RPC `api_layers` / `api_habitat`.
4. **Parameter fatigue, faktor cuaca BBM, penalti keramaian** — perlu kalibrasi/validasi pihak konservasi.
5. **Kuota zona terbatas** — total untuk semua nelayan (implementasi sekarang) atau per nelayan?
6. **Rehab kedaluwarsa** (`effective_until` lewat) — otomatis tidak berlaku (implementasi sekarang, enforcement `expired`) atau perlu konfirmasi admin?
7. **Pembagian tangkapan multi-titik** — `reported_catch_kg` per titik jika semua diisi, selain itu proporsional durasi, selain itu rata (implementasi sekarang).
8. **Dermaga** — daftar dermaga resmi atau titik berangkat bebas (sekarang bebas, ≤ 5 km dari grid).
9. **Metadata data** — satuan semua layer, arti 24 entri klorofil (= 24 bulan 2024-01…2025-12 menurut audit), arti kedalaman 5000, `is_sea` dan `coral_sensitivity` per grid.

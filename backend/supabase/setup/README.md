# Setup hosted Supabase dan contoh RPC

Proyek REEFISH yang dicatat dalam laporan adalah `upyahsecuorqghcghflg`. Source skema adalah `../migrations/*.sql`; `hosted_setup.sql` merupakan bundle instalasi baru yang dihasilkan dan tidak diedit manual. Jangan jalankan bundle itu pada proyek hosted berisi data.

Laporan verifikasi 16 Oktober 2026 mencatat migrasi grid, Journey, zona/heatmap, layer, push, optimasi rekomendasi, dan refresh asinkron telah diterapkan. File [`integration-verification.json`](integration-verification.json) adalah snapshot bukti bertanggal, bukan pemeriksaan status live. Sebelum deployment ke target mana pun, periksa `npx supabase migration list` dan cocokkan versi remote; jangan mengulang migrasi yang telah tercatat.

Untuk membuat ulang bundle instalasi baru, jalankan perintah berikut dari direktori `backend/supabase`:

```sh
{ printf -- '-- GENERATED: do not edit. Source of truth is supabase/migrations/*.sql.\n-- Regenerate from backend/supabase: see setup/README.md.\n-- Run once in the Supabase SQL Editor on an empty project; everything commits or nothing does.\nbegin;\n'; for f in migrations/202610161*.sql; do printf '\n-- ===== %s =====\n' "$f"; cat "$f"; done; printf '\ncommit;\n'; } > setup/hosted_setup.sql
```

## 1. Membuat skema

**A. CLI.** Gunakan hanya setelah memastikan ledger target dan source cocok. `db push` menerapkan semua migrasi lokal yang belum tercatat pada target.

```sh
npx supabase login
npx supabase link --project-ref upyahsecuorqghcghflg   # tautan lokal tersimpan di backend/supabase/.temp
npx supabase migration list   # cocokkan daftar lokal dan remote terlebih dahulu
npx supabase db push
```

**B. SQL Editor.**
1. Buka Table Editor dan pastikan `profiles`, `zones`, dan `grid_cells` belum ada. Skrip gagal jika tabel tersebut sudah tersedia. Tabel grid dari main (`map_areas`, `grid_restrictions`, dan seterusnya) diasumsikan ada dan tidak diubah.
2. Buka SQL Editor dan buat kueri baru.
3. Tempel seluruh `hosted_setup.sql` lalu jalankan. Skrip memakai satu transaksi, sehingga semua perubahan berhasil bersama atau seluruhnya dibatalkan.

Cara SQL Editor tidak mencatat riwayat migrasi CLI. Sebelum memakai CLI pada proyek tersebut, bandingkan daftar migrasi lokal dan remote. Gunakan `npx supabase migration repair --help` dan rekonsiliasi hanya versi yang sudah dipastikan diterapkan; jangan menyalin daftar versi tanpa memeriksa ledger.

## 2. Autentikasi

Auth menggunakan Supabase Auth. Aplikasi mobile memakai repository autentikasi untuk sign-up, verifikasi OTP, dan login dengan nomor telepon.
- Provider dan konfirmasi phone diatur lewat Dashboard → Authentication → Sign In / Providers → Phone.
- **Jangan jalankan `npx supabase config push`**: `config.toml` dipakai untuk pengembangan lokal dan dapat menimpa setelan hosted.
- Saat sign-up, trigger `handle_new_user` menyalin `auth.users.phone` (E.164 tanpa `+`) ke `profiles.phone`.

Status provider dan pengiriman OTP harus diperiksa di Supabase Dashboard saat demo. Laporan integrasi hosted mencatat autentikasi HTTP probe berhasil, tetapi tidak menguji perubahan konfigurasi provider. Jangan simpulkan SMS terkirim hanya dari tes database atau login password. Konfigurasi phone/Twilio bila memang hendak menguji SMS:
1. Di Twilio Console, buat Messaging Service dengan pengirim yang dapat menjangkau nomor Indonesia. Catat Account SID, Auth Token, dan Messaging Service SID secara aman.
2. Di Supabase Dashboard → Authentication → Sign In / Providers → Phone, aktifkan provider Twilio, isi nilainya, aktifkan konfirmasi nomor, lalu simpan.
3. Untuk demo, nomor uji dan OTP tetap dapat ditambahkan pada halaman yang sama tanpa biaya SMS.
4. Verifikasi dengan sign-up nomor aktif, penerimaan SMS, `verifyOTP`, lalu `signInWithPassword(phone, password)`. Pastikan `select phone from profiles` menampilkan nomor tanpa `+`.

Secara lokal, `config.toml` memakai provider dummy dan OTP tetap untuk fixture pengembangan; tidak ada SMS yang dikirim.

## 3. Impor data

Pemeriksaan peta, rekomendasi, dan cakupan pilot memerlukan `grid_cells` dan `cluster_predictions`.
1. Jalankan pembuat CSV dari direktori `backend` dengan sumber lokal yang tersedia. Rekap demo hosted mencatat satu periode (`2025-12`), 31.354 baris prediksi dan 31.354 nilai `potensi_ikan`; hasil itu bukan bukti bahwa seluruh 24 periode sudah tersedia.

   ```sh
   M=../machine-learning/data
   python scripts/geojson_to_csv.py $M/geojson out --coral $M/processed/geodata/coral.geojson \
     --mangrove $M/processed/geodata/mangrove.geojson --potensi-ikan $M/raw/layers/potensi_ikan.csv
   ```

2. Dari direktori `backend`, impor lewat Table Editor (`grid_cells`, lalu `cluster_predictions`), atau jalankan perintah berikut. Berkas CSV berada di `backend/out/`:

```sh
psql "$SUPABASE_DB_URL" -c "\copy grid_cells(grid_id, geom) from 'out/grid_cells.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy cluster_predictions from 'out/cluster_predictions.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy coral_areas(id, value, geom) from 'out/coral_areas.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy mangrove_areas(id, gridcode, year, area_km2, area_clip_km2, geom) from 'out/mangrove_areas.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy grid_layers(grid_id, potensi_ikan) from 'out/grid_layers.csv' csv header"
psql "$SUPABASE_DB_URL" -c "select private.refresh_coral(); select private.daily_refresh();"
```

Untuk proyek yang sudah berisi data, jalankan dari direktori `backend` dan buat ulang batch impor terbatas serta idempoten dengan `python scripts/prepare_hosted_layers.py --help` (lihat [laporan integrasi](../../../docs/frontend/hackathon-integration.md)).

`scripts/hosted_load.sh` dari direktori `backend` hanya untuk **impor pertama ke proyek kosong**: skrip melewatkan seluruh impor begitu `grid_cells` sudah berisi baris, sehingga ini bukan pemuat inkremental.

Langkah refresh menandai sel karang dan menerbitkan heatmap awal. Setelah itu, `pg_cron` menjalankan `private.daily_refresh()` setiap hari pukul 00:10 WIB (job `heatmap-daily`) dan memproses permintaan refresh manual dari web admin setiap 10 detik (job `heatmap-refresh-jobs`). Periksa keduanya di Database → Cron.

## 4. Data demo (opsional)

`supabase/seed/demo.sql` menambahkan data demo persisten untuk aplikasi dan dashboard. Ini bukan tes, dan barisnya akan tetap berada di database. Jalankan perintah impor dari direktori `backend`; data dari bagian 3 harus tersedia terlebih dahulu.

Skenario menggunakan titik pelabuhan Sendang Biru (-8.43, 112.68):

| Akun fixture | Skenario |
|---|---|
| `demo-baru@demo.reefish.app` | onboarding → rekomendasi |
| `demo-aktif@demo.reefish.app` | riwayat perjalanan untuk baseline dan habitual |
| `demo-n01` … `demo-n20` | aktivitas pada sel karang untuk skenario fatigue/flag |
| `demo-admin@demo.reefish.app` | skenario zona kuota dan rehab untuk dashboard konservatif |

Jalankan dengan persetujuan eksplisit; tanpa itu skrip menolak:

```sh
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -c "set reefish.allow_demo = 'on'" -f supabase/seed/demo.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/demo_reset.sql   # hapus seluruh data demo
```

Di SQL Editor, letakkan `set reefish.allow_demo = 'on';` tepat di atas isi `demo.sql`.

Catatan:
- Jika dijalankan lagi, skrip mengganti data demo sebelumnya dan menggunakan tanggal hari ini.
- `demo_reset` hanya menghapus akun `*@demo.reefish.app`, zona `Demo %`, dan pengaruhnya pada heatmap.
- Akun dan password demo dikelola sebagai fixture lokal/hosted; jangan salin kredensial ke dokumentasi publik. Ketersediaan metode login hosted perlu dikonfirmasi terhadap provider aktif.

## 5. Pemeriksaan

Jalankan `supabase/tests/fixed_grid.sql`, `supabase/tests/nelayan.sql`, `supabase/tests/zones_heatmap.sql`, dan `supabase/tests/layers.sql` di SQL Editor sesuai prasyarat masing-masing. File SQL tersebut berada di repo di bawah `backend/supabase/tests/`. `scripts/hosted_load.sh` dari direktori `backend` juga menjalankan tes, tetapi hanya cocok untuk impor pertama pada proyek kosong. Tes membuat user sementara, menguji alur RPC, lalu melakukan rollback. Hasil berhasil menampilkan notice `nelayan smoke test passed`.

## 6. Push notifications (FCM)

Perubahan zona menambahkan baris ke `push_outbox`. Edge Function `push-dispatch` mengambil antrean melalui `api_internal_push_claim`, mengirim pesan FCM HTTP v1 untuk tiap token perangkat, lalu melaporkan hasil lewat `api_internal_push_done`. Pesan gagal dicoba ulang hingga tiga kali; token mati dihapus.

Deploy fungsi (tanpa secret, fungsi menjawab `{"skipped": ...}` dan tidak mengubah antrean):

```sh
npx supabase functions deploy push-dispatch
```

Jalankan perintah deploy dari direktori `backend/supabase`.

Kode fungsi dan skema antrean tersedia. Rekap integrasi hosted menyebut proyek/kredensial Firebase dan registrasi perangkat belum dikonfigurasi, sehingga belum ada bukti push diterima perangkat. Untuk menyiapkannya:
1. Firebase Console → Project settings → Service accounts → buat private key JSON. Jangan masukkan file ini ke Git.
2. `npx supabase secrets set FCM_SERVICE_ACCOUNT="$(cat firebase-sa.json)"`
3. Jadwalkan setiap menit dari SQL Editor sebagai postgres. Simpan service-role key di Vault terlebih dahulu (Project Settings → API Keys → Legacy → `service_role`; fungsi membandingkannya dengan `SUPABASE_SERVICE_ROLE_KEY` miliknya):

```sql
select vault.create_secret('<service_role key>', 'service_role_key');
select cron.schedule('push-dispatch', '* * * * *', $$
  select net.http_post(
    url := 'https://upyahsecuorqghcghflg.supabase.co/functions/v1/push-dispatch',
    headers := jsonb_build_object('Authorization', 'Bearer ' ||
      (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')))
$$);
```

4. Verifikasi dengan mengubah zona dekat nelayan yang perangkatnya terdaftar. Kueri `select status, attempts from push_outbox order by id desc limit 5` harus menunjukkan `sent`.

Flutter juga memerlukan `google-services.json` dari proyek Firebase yang sama dan harus memanggil `api_register_device` dengan token perangkat.

## 7. Contoh kueri per endpoint

RPC nelayan memerlukan role `nelayan` (selain itu menghasilkan `FORBIDDEN`). Error diterima sebagai `PostgrestException`:
- `message` = kode error, misalnya `BOAT_LIMIT_REACHED`
- `hint` = pesan untuk pengguna dalam bahasa Indonesia
- `details` = teks berformat JSON

Skema lengkap ada di `contracts/nelayan-api.openapi.yaml`.

Untuk mencoba kueri di SQL Editor sebagai user tertentu, bungkus kueri seperti berikut. Ganti `<uuid>` dengan ID dari Authentication → Users.

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
-- tulis kueri yang ingin dicoba di sini
rollback;  -- gunakan commit jika perubahan ingin disimpan
```

### Profil dan kapal

| Endpoint | Flutter | SQL Editor |
|---|---|---|
| me | `supabase.rpc('api_me')` | `select api_me();` |
| createBoat | `supabase.rpc('api_create_boat', params: {'p': {'name': 'KM Sumber Rejeki', 'engine_hp': 15, 'boat_length_m': 7, 'fuel_type': 'solar', 'home_port': {'lat': -8.43, 'lng': 112.68}}})` | `select api_create_boat('{"name":"KM Sumber Rejeki","engine_hp":15,"boat_length_m":7,"home_port":{"lat":-8.43,"lng":112.68}}');` |
| updateBoat | `supabase.rpc('api_update_boat', params: {'p_id': boatId, 'p': {'engine_hp': 20}})` | `select api_update_boat('<boat uuid>', '{"engine_hp":20}');` |

### Perjalanan

| Endpoint | Flutter | SQL Editor |
|---|---|---|
| Kirim perjalanan | `supabase.rpc('api_post_trip', params: {'p': trip})` | lihat contoh berikut |
| getHistoryTrip | `supabase.rpc('api_list_trips', params: {'p_page': 1, 'p_limit': 20, 'p_sort': '-departed_at'})` | `select api_list_trips(1, 20, null, null, null, '-departed_at');` |
| getTripDetail | `supabase.rpc('api_trip_detail', params: {'p_id': tripId, 'p_track': 'simplified'})` | `select api_trip_detail('<trip uuid>', 'simplified');` |

```sql
select api_post_trip('{
  "client_trip_id": "c0ffee00-0000-4000-8000-000000000001",
  "source": "onboarding",
  "departed_at": "2026-10-15T21:00:00Z",
  "returned_at": "2026-10-16T05:00:00Z",
  "fuel_liters": 25.5,
  "catch_kg": 40,
  "fishing_points": [{"lat": -8.50, "lng": 112.70, "flag_source": "manual"}]
}');
```

Pengiriman ulang `client_trip_id` yang sama mengembalikan `replay: true` dan tidak menulis baris baru. Jalankan kueri sekali lagi untuk memeriksanya.

### Konfigurasi, peta, dan zona

| Endpoint | Flutter | SQL Editor |
|---|---|---|
| Konfigurasi mobile (tanpa login) | `supabase.rpc('api_mobile_config')` | `select api_mobile_config();` |
| Peta spot penangkapan | `supabase.rpc('get_fishing_spots', params: {'p_period': '2025-12', 'p_min_level': 4})` | `select get_fishing_spots('2025-12', 4);` |
| Peta cluster (konservatif) | `supabase.rpc('get_clusters', params: {'p_period': '2025-12'})` | `select get_clusters('2025-12', 1);` |
| Metadata grid / mask laut | `supabase.rpc('api_grid_meta')`, `supabase.rpc('api_sea_mask')` | `select api_grid_meta();` |
| Zona (`ZoneEntry`) | `supabase.rpc('api_zones', params: {'p_include_outline': true})` | `select api_zones(null, true);` |
| Heatmap | `supabase.rpc('api_heatmap', params: {'p_window': '30d'})` | `select api_heatmap('30d');` |
| Layer ML per periode | `supabase.rpc('api_layers', params: {'p_period': '2025-12'})` | `select api_layers('2025-12');` |
| Karang + mangrove | `supabase.rpc('api_habitat')` | `select api_habitat();` |
| Versi/perubahan heatmap | `supabase.rpc('api_heatmap_version')`, `supabase.rpc('api_heatmap_changes', params: {'p_since': v})` | `select api_heatmap_changes(12);` |
| Setelah sinkronisasi (pengganti X-Heatmap-Version) | `supabase.rpc('api_sync_seen', params: {'p_heatmap_version': v})` | `select api_sync_seen(12);` |
| Perangkat push | `supabase.rpc('api_register_device', params: {'p': {'fcm_token': token}})` | `select api_register_device('{"fcm_token":"abc1234567"}');` |

### Admin konservatif (AGENTS.md bagian 12.A)

| Endpoint | SQL Editor |
|---|---|
| previewZona | `select api_admin_preview_zone('{"grid_ids":["X150_Y040","X151_Y040"]}');` |
| createZona | `select api_admin_create_zone('{"name":"Karang Uji","status":"restricted","grid_ids":["X150_Y040"],"rules":{"max_catch_kg_per_period":500,"period":"weekly"},"reason":"Fatigue tinggi"}');` |
| Buat zona dari poligon (sel dengan titik tengah di dalam poligon) | `select api_admin_create_zone('{"name":"Karang Gambar","status":"rehab","polygon":{"type":"Polygon","coordinates":[[[112.60,-8.50],[112.62,-8.50],[112.62,-8.48],[112.60,-8.48],[112.60,-8.50]]]},"reason":"Rehabilitasi"}');` |
| readListZona / readDetailZona | `select api_admin_list_zones();`, `select api_admin_zone_detail('<zone uuid>');` |
| editZona | `select api_admin_edit_zone('<zone uuid>', '{"name":"Karang Uji B","reason":"Ganti nama","version":1}');` |
| editGridZona | `select api_admin_edit_zone_grids('<zone uuid>', '{"add":["X151_Y040"],"reason":"Perluasan","version":2}');` |
| editStatusZona | `select api_admin_edit_zone_status('<zone uuid>', '{"status":"normal","reason":"Pulih","version":3}');` |
| zoneHistory | `select api_admin_zone_history('<zone uuid>');` |
| getGridDetail | `select api_admin_grid_detail('X150_Y040');` |
| listFlags / dismissFlag | `select api_admin_list_flags();`, `select api_admin_dismiss_flags('{"grid_ids":["X150_Y040"],"reason":"Musiman"}');` |
| refreshHeatmap / getRefreshStatus | `select api_admin_refresh_heatmap('{"scope":"all","reason":"Update data"}');`, `select api_admin_refresh_status('<job uuid>');` |
| statsSummary | `select api_admin_stats_summary('30d');` |
| Saran sistem (restrict + reopen) | `select api_admin_suggestions();`, `select api_admin_suggestions('reopen');` |
| Profil admin | `select api_me();` menghasilkan role `konservatif`, `next_step` `done` |
| Flag otomatis ke restricted (hanya service_role / postgres) | `select api_internal_auto_flag(null, true);` |

Dari Next.js pemanggilannya sama, misalnya `supabase.rpc('api_admin_create_zone', { p: {...} })`.

### Autentikasi native

Di Flutter, gunakan `supabase.auth.signUp(phone: '+6281234567890', password: ...)`, lalu `verifyOTP(type: OtpType.sms, phone, token)`. Login berikutnya memakai `signInWithPassword(phone: ..., password: ...)`.
Kirim `session.accessToken` ke Go service pada header `Authorization: Bearer`.

### Mengubah role akun menjadi konservatif (SQL Editor, sebagai postgres)

```sql
update profiles set role = 'konservatif' where phone = '6281234567890';
```

### Go service (komputasi, bukan RPC Supabase)

Panggil `GET /api/v1/recommendations` dan `GET /api/v1/weather` dengan `Authorization: Bearer <access_token>`. Service ini memanggil `api_rec_context`, `api_save_recommendations`, dan `api_in_pilot` ke Supabase.

# Web (Next.js) — admin kawasan (konservatif)

Web dan mobile memakai kontrak backend yang sama; aturan akses tidak hanya diterapkan di UI.

Alur keputusan zona (bukan lagi mengikuti Figma):

1. Dashboard menampilkan heatmap per sel grid 500 m (MapLibre).
2. Admin memilih beberapa grid langsung di peta. Grid yang sudah masuk zona aktif tidak bisa dipilih.
3. Tombol **Buat keputusan** aktif setelah minimal satu grid dipilih.
4. Pendataan zona (`/area/baru?grids=…`) mengambil agregat grid terpilih (`api_admin_preview_zone`) dan status seluruh zona, lalu mengisi field `api_admin_create_zone`:
   - `restricted`: kuota agregat seluruh grid (kg dan/atau trip per minggu/bulan, jadwal buka opsional), ditampilkan bersama kapasitas aktivitas grid saat ini.
   - `rehab`: zero tolerance, grid dinonaktifkan.
   - `normal` tidak didata; grid tanpa zona sudah normal.
5. Simpan, lalu diarahkan ke detail keputusan.

Riwayat keputusan (`/area/riwayat`) menampilkan semua zona, termasuk yang sudah kembali normal, beserta linimasa perubahan. Zona yang masih berlaku bisa dikembalikan ke normal (`api_admin_edit_zone_status` dengan `normal`: zona diarsipkan, gridnya dilepas).

## Menjalankan

```sh
npm install        # postinstall menyalin worker MapLibre ke public/
npm run dev        # http://localhost:3000
npm run build && npm run lint
npm test           # rumus grid (vektor kontrak) + service zona
```

Env (opsional, `.env.local`):

```
NEXT_PUBLIC_SUPABASE_URL=https://upyahsecuorqghcghflg.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
```

- Tanpa env: **mode demo**. Login langsung ke dashboard, semua data simulasi.
- Dengan env: `src/proxy.ts` mengarahkan pengguna yang belum login ke `/login`. Login memakai telepon/email + kata sandi dan hanya menerima role `konservatif` (`api_me`).

## Halaman

| Route | Isi |
|---|---|
| `/login` | Login konservatif (mode demo tanpa env) |
| `/dashboard` | Heatmap, multi-select grid, tombol Buat keputusan, zona aktif; `?data=kosong` = keadaan belum ada data |
| `/area/baru?grids=X…,X…` | Pendataan zona: agregat grid, status seluruh zona, form keputusan |
| `/area/[id]` | Detail keputusan: agregat, kuota berjalan, riwayat, Ubah status |
| `/area/[id]/edit` | Edit nama, kuota, masa berlaku, catatan (`api_admin_edit_zone`) |
| `/area` | Zona aktif per status |
| `/area/riwayat` | Riwayat keputusan + Kembalikan ke normal |
| `/pantau-pelanggaran` | Daftar indikasi, detail, kirim peringatan |

## Data

Semua data masih **simulasi**, tapi bentuknya sama dengan kontrak `contracts/map-zones-api.openapi.yaml`:
- Zona: `features/decisions/services/zones.ts` meniru `api_admin_preview_zone`, `api_admin_create_zone`, `api_admin_list_zones`, `api_admin_zone_detail`, `api_admin_edit_zone`, `api_admin_edit_zone_status`, `api_admin_zone_history` (input, output, dan kode error yang sama). Disimpan di localStorage per browser. Untuk menyambung ke Supabase, ganti isi fungsi-fungsinya dengan `supabase.rpc(...)`.
- Heatmap: `features/geo/mock-heatmap.ts`, laut selatan Pulau Sempu.
- Pelanggaran: `features/violations/mock.ts`.

`npm test` menjalankan test grid dan test service zona (`zones.test.ts`).

Belum ada RPC backend untuk nelayan unik per sel dan daftar indikasi pelanggaran + kirim peringatan.

Citra satelit: Esri World Imagery (butuh internet; tanpa itu peta tetap tampil dengan latar gelap).

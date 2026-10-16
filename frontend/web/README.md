# Web (Next.js) — admin kawasan (konservatif)

Web dan mobile memakai kontrak backend yang sama; aturan akses tidak hanya diterapkan di UI.

Produksi: https://reefish-admin.vercel.app (Vercel, proyek `reefish-admin`, scope `wildannovs-projects`). Deployment memakai unggahan source lewat CLI; belum ada auto-deploy GitHub. Supabase URL dan publishable key disetel di environment Production dan Preview Vercel. Tidak ada service-role key di frontend.

Alur keputusan zona (bukan lagi mengikuti Figma):

1. Dashboard menampilkan heatmap per sel grid 500 m (MapLibre).
2. Admin memilih beberapa grid langsung di peta. Grid `normal` dan `restricted` bisa dipilih:
   - restricted **flag sistem** (sel normal dengan fatigue kritis, ditandai otomatis) menunggu keputusan admin;
   - restricted **zona admin** bisa diputuskan ulang; sel dipindah ke keputusan baru (`on_conflict: move`), zona asal yang kosong otomatis kembali normal.
   - Grid `rehab` terkunci (zero tolerance); ubah lewat detail zona rehab-nya.
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

Env (`.env.local` untuk lokal, project environment di Vercel):

```
NEXT_PUBLIC_SUPABASE_URL=https://upyahsecuorqghcghflg.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
```

- Tanpa env saat development: **mode demo lokal**. Tanpa env saat production: akses ditolak dengan status 503; tidak ada bypass login.
- Dengan env: `src/proxy.ts` mengarahkan pengguna yang belum login ke `/login`. Login memakai telepon/email + kata sandi dan hanya menerima role `konservatif` (`api_me`).

## Halaman

| Route | Isi |
|---|---|
| `/login` | Login konservatif (demo hanya saat development tanpa env) |
| `/dashboard` | Heatmap, multi-select grid, tombol Buat keputusan, zona aktif; `?data=kosong` = keadaan belum ada data |
| `/area/baru?grids=X…,X…` | Pendataan zona: agregat grid, status seluruh zona, form keputusan |
| `/area/[id]` | Detail keputusan: agregat, kuota berjalan, riwayat, Ubah status |
| `/area/[id]/edit` | Edit nama, kuota, masa berlaku, catatan (`api_admin_edit_zone`) |
| `/area` | Zona aktif per status |
| `/area/riwayat` | Riwayat keputusan + Kembalikan ke normal |
| `/pantau-pelanggaran` | Production: keterangan fitur belum tersedia; development tanpa env: contoh simulasi |

## Data

Data production memakai kontrak `contracts/map-zones-api.openapi.yaml`:
- Zona: `features/decisions/services/zones.ts` memanggil RPC preview/create/list/detail/edit/status/history, mempertahankan version checks dan error backend. Fixture localStorage dipisah ke `demo-zones.ts` dan hanya dipakai tanpa konfigurasi di development.
- Heatmap: `features/geo/services/heatmap.ts` membaca `api_heatmap` untuk periode 7/30 hari, termasuk seluruh 31.354 sel agar grid tanpa aktivitas tetap bisa dipilih. Dashboard memperbarui heatmap setiap 30 detik. Warna production menunjukkan fatigue; statistik nelayan unik dan tren yang belum disediakan RPC tampil sebagai belum tersedia.
- Zona rehab aktif diterbitkan Supabase ke `get_grid_lock_snapshot`, yang sudah dibaca aplikasi mobile. Kembali normal mengarsipkan zona dan melepas grid. Mobile mengambil status saat membuka peta, memperbarui status, masa snapshot habis, dan sebelum menyimpan lokasi penangkapan; ini bukan push instan.
- Pelanggaran/jejak/peringatan belum terhubung: halaman production menampilkan keterangan belum tersedia, tanpa data atau tombol kirim simulasi.

`npm test` menjalankan test grid, parser heatmap, service demo, serta adapter RPC zona.

Deploy ulang: `vercel --prod --yes --scope wildannovs-projects` dari direktori ini setelah build/test. `vercel.json` menetapkan framework Next.js; postinstall tetap menyalin worker MapLibre. Konfigurasi `.vercel` dan `.env.local` diabaikan Git. Login admin memerlukan role `konservatif`; role tersebut hanya diberikan dari backend, bukan form publik.

Belum ada RPC backend untuk nelayan unik per sel dan daftar indikasi pelanggaran + kirim peringatan.

Citra satelit: Esri World Imagery (butuh internet; tanpa itu peta tetap tampil dengan latar gelap).

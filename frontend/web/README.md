# Web (Next.js) — admin kawasan (konservatif)

Web dan mobile memakai kontrak backend yang sama; aturan akses tidak hanya diterapkan di UI.

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

Env wajib di `.env.local` (gitignored):

```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321     # Supabase lokal (npx supabase start); hosted: https://upyahsecuorqghcghflg.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>            # lokal: npx supabase status
```

- `src/proxy.ts` mengarahkan pengguna yang belum login ke `/login`. Login memakai telepon/email + kata sandi dan hanya menerima role `konservatif` (`api_me`).
- Akun demo lokal (`backend/supabase/seed/demo.sql`): `demo-admin@demo.reefish.app` / `Demo#2026`.

## Halaman

| Route | Isi | RPC |
|---|---|---|
| `/login` | Login konservatif | Auth + `api_me` |
| `/dashboard` | Heatmap (fatigue / tekanan / CPUE, 7 / 30 hari) yang diperbarui otomatis, lapisan ML per periode, overlay terumbu karang & mangrove, garis zona + popup, multi-select grid (`?grids=` pra-pilih), detail grid (+ nilai ML), saran sistem (+ dismiss), ringkasan, hitung ulang heatmap | `api_sea_mask`, `api_heatmap`, `api_heatmap_version`, `api_heatmap_changes`, `api_layers`, `api_habitat`, `api_zones`, `api_admin_grid_detail`, `api_admin_suggestions`, `api_admin_dismiss_flags`, `api_admin_stats_summary`, `api_admin_list_zones`, `api_admin_refresh_heatmap`, `api_admin_refresh_status` |
| `/area/baru?grids=X…,X…` | Pendataan zona | `api_admin_preview_zone`, `api_admin_create_zone` (`on_conflict: move`) |
| `/area/[id]` | Detail keputusan, edit grid, ubah status | `api_admin_zone_detail`, `api_admin_zone_history`, `api_admin_edit_zone_grids`, `api_admin_edit_zone_status` |
| `/area/[id]/edit` | Nama, kuota, masa berlaku, catatan | `api_admin_edit_zone` |
| `/area` | Zona aktif per status | `api_admin_list_zones` |
| `/area/riwayat` | Riwayat semua keputusan + kembalikan ke normal | `api_admin_list_zones`, `api_admin_zone_history` (per zona), `api_admin_edit_zone_status` |
| `/flags` | Flag sistem aktif / di-dismiss, filter karang, urutan, dismiss, pilih di peta | `api_admin_list_flags`, `api_admin_dismiss_flags` |

Pantau Pelanggaran disembunyikan sampai ada RPC-nya (kode lama ada di riwayat git, commit `030ee07`).

## Data

Semua halaman memakai RPC Supabase (`features/decisions/services/zones.ts`, `features/geo/services/heatmap.ts`), dipanggil sebagai pengguna yang login (RLS + cek role di fungsi SQL). Error `private.fail` dipetakan ke `ApiError` (`lib/api/error.ts`).

Aturan UI di atas backend: grid `rehab` tidak bisa dipilih atau dipindah dari peta (zero tolerance); grid `restricted` dipindah ke keputusan baru.

`npm test` menjalankan test rumus grid dan parser heatmap/sea mask/error.

Citra satelit: Esri World Imagery (butuh internet; tanpa itu peta tetap tampil dengan latar gelap).

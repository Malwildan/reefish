# Web (Next.js) — admin kawasan (konservatif)

Web dan mobile memakai kontrak backend yang sama; aturan akses tidak hanya diterapkan di UI.

Hasil slicing Figma `JOINTS-BISMILLAH-YAALLAH-JUARA-1`, section **High-Fidelity → Admin** (flow 01–09). Peta memakai heatmap per sel grid 500 m (MapLibre), bukan garis putus-putus seperti di Figma.

## Menjalankan

```sh
npm install        # postinstall menyalin worker MapLibre ke public/
npm run dev        # http://localhost:3000
npm run build && npm run lint
npm test           # rumus grid vs contracts/fixtures/grid-index-vectors.json
```

Env (opsional, `.env.local`):

```
NEXT_PUBLIC_SUPABASE_URL=https://upyahsecuorqghcghflg.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
```

- Tanpa env: **mode demo**. Login langsung ke dashboard, semua data simulasi.
- Dengan env: `src/proxy.ts` mengarahkan pengguna yang belum login ke `/login`. Login memakai telepon/email + kata sandi dan hanya menerima role `konservatif` (`api_me`).

## Halaman

| Route | Figma |
|---|---|
| `/login` | (tidak ada di Figma; memakai token yang sama) |
| `/dashboard` | 01.1 Dashboard; `?grid=X100_Y145` = 01.2 Detail grid; `?notice=dibuat\|draf\|disimpan\|dihapus` = varian badge; `?data=kosong` = 08 Belum ada data |
| `/area` | 01.3 Area, 03.2 daftar draf, 05.1–05.2 hapus (dialog) |
| `/area/baru` | 02.1 Buat keputusan (`?grid=` mengisi grid awal; klik sel di peta untuk menambah/mengurangi) |
| `/area/[id]` | 02.3 Terbit, 02.4 Pengumuman tersalin, 03.3 Draf, 06.2 Dicabut, 08 Berakhir; `?aksi=cabut` = 06.1 Form pencabutan |
| `/area/[id]/edit` | 04.1 Edit keputusan |
| `/pantau-pelanggaran` | 07A/07B daftar nelayan, `?id=` = detail + kirim peringatan |

## Data

Semua data masih **simulasi**:
- Keputusan: `features/decisions/services/store.ts` (localStorage per browser). "Tutup sementara" = zona `rehab`, "Batasi kuota" = zona `restricted` di backend.
- Heatmap: `features/geo/mock-heatmap.ts`, area laut selatan Pulau Sempu.
- Pelanggaran: `features/violations/mock.ts`.

Belum ada RPC backend untuk: nelayan unik per sel, status draf/terbit/dicabut + pengumuman, dan daftar indikasi pelanggaran + kirim peringatan. Sambungkan lewat `lib/supabase` saat RPC-nya ada (`api_admin_create_zone`, `api_admin_list_zones`, `api_admin_edit_zone_status`, `api_heatmap`, …).

Citra satelit: Esri World Imagery (butuh internet; tanpa itu peta tetap tampil dengan latar gelap).

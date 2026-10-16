# Web admin — konservatif

Aplikasi Next.js ini mendukung peran **konservatif**, sebagai pasangan [aplikasi mobile nelayan](../mobile/README.md). Aplikasi web menampilkan indikator per grid dan mencatat keputusan pengelolaan; aplikasi mobile membaca status tersebut saat menampilkan petak penangkapan. Keduanya menggunakan kontrak Supabase bersama, sedangkan RPC database menegakkan peran dan kebijakan akses.

## Menjalankan secara lokal

Dari direktori ini:

```sh
npm install
npm run dev
```

Buka `http://localhost:3000`. Perintah `npm install` menjalankan postinstall yang menyalin worker MapLibre ke `public/`.

Buat berkas `.env.local` (diabaikan Git) berisi URL Supabase dan publishable/anon key:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<publishable-or-anon-key>
```

Untuk Supabase lokal, jalankan proyek dari `backend/` dengan Supabase CLI dan ambil key lokal melalui `npx supabase status`. Aplikasi web memanggil RPC Supabase dengan sesi pengguna. Jangan masukkan service-role key ke konfigurasi browser. Pengguna yang belum login diarahkan ke `/login`; setelah login, `api_me` harus mengembalikan peran `konservatif`. RPC admin tetap memeriksa peran di backend.

Agar dashboard lokal menampilkan data, terapkan migrasi backend, impor grid dan data sumber yang diperlukan, lalu bila perlu tambahkan data demo. Ikuti [panduan setup Supabase, impor data, dan seed demo](../../backend/supabase/setup/README.md#4-data-demo-opsional). Seed membuat data persisten dan memerlukan opt-in eksplisit; seed bukan bagian dari `npm install` atau fixture pengujian. Panduan setup tersebut memuat rincian akun demo; kredensial tidak dicantumkan di sini.

## Alur keputusan

1. Login dengan akun berperan `konservatif`, lalu buka `/dashboard`. Peta MapLibre menampilkan heatmap aktivitas, pilihan rentang 7 atau 30 hari, layer dan periode ML yang tersedia, overlay karang/mangrove opsional, garis zona, dan flag sistem. Pilih grid normal atau restricted. Grid rehab terkunci.
2. Pilih **Buat keputusan** untuk membuka `/area/baru?grids=…`. Halaman ini menampilkan pratinjau agregat grid terpilih dan konflik zona. Isi nama zona, masa berlaku, lalu pilih `restricted` dengan kuota agregat tangkapan/trip (jadwal buka opsional), atau `rehab` dengan penutupan zero tolerance.
3. Simpan dan periksa keputusan serta riwayatnya di `/area/[id]`. Grid restricted yang sudah ada dapat dipindahkan ke keputusan lain; grid rehab tetap terkunci dan hanya dapat diubah melalui zona rehab-nya. `/area/riwayat` menampilkan keputusan yang telah diarsipkan serta menyediakan aksi mengembalikan zona aktif ke normal.
4. Buka `/flags` untuk meninjau flag sistem, menundanya sementara, atau memilih grid di peta. Tombol **Hitung ulang heatmap** di dashboard memasukkan permintaan refresh ke antrean; statusnya dibaca melalui RPC refresh.

Untuk demo lokal singkat yang dapat diulang, gunakan skenario admin hasil seed setelah menyelesaikan setup di atas: login, tunjukkan heatmap dan overlay zona, pilih satu atau beberapa grid yang memenuhi syarat, tinjau pratinjau, simpan keputusan, lalu buka detail dan riwayatnya. Baris sumber dan zona dari seed adalah data simulasi, bukan bukti hasil konservasi terukur. Tanpa impor grid dan heatmap, halaman dapat kosong; tanpa backend yang valid dan peran yang berwenang, operasi RPC yang dilindungi akan gagal.

## Rute dan bukti implementasi

| Rute | Fungsi |
|---|---|
| `/login` | Login kata sandi Supabase dan pemeriksaan peran melalui `api_me` |
| `/dashboard` | Heatmap, overlay ML/habitat, detail dan pemilihan grid, flag/saran, ringkasan, refresh asinkron |
| `/area` | Zona aktif berdasarkan status |
| `/area/baru?grids=…` | Pratinjau dan pembuatan zona dari grid terpilih |
| `/area/[id]`, `/area/[id]/edit` | Detail/riwayat zona serta edit metadata, grid, dan status |
| `/area/riwayat` | Riwayat keputusan, termasuk zona yang dikembalikan ke normal |
| `/flags` | Flag sistem aktif/ditunda dan pemilihan grid di peta |

Implementasi memisahkan halaman rute, komponen fitur, dan modul layanan. Layanan zona membungkus RPC admin bersama; tipe datanya merujuk pada [kontrak API peta dan zona](../../contracts/map-zones-api.openapi.yaml). Parser peta membaca hasil RPC, rumus grid mengikuti kontrak grid bersama, dan fungsi database menegakkan validasi, otorisasi peran, serta aturan zero tolerance untuk rehab. Artefak ini dapat ditinjau di kode, tetapi tidak membuktikan dampak lapangan.

## Pemeriksaan lokal

```sh
npm run build
npm run lint
npm test
```

`npm test` menjalankan pengujian indeks grid dan parser heatmap/sea-mask/error. Perintah ini tersedia untuk verifikasi lokal; tidak dijalankan saat memperbarui README.

## Deployment dan batas bukti

Laporan integrasi mencatat deployment admin di [reefish-admin.vercel.app](https://reefish-admin.vercel.app), migrasi/worker refresh Supabase hosted, dan akun berperan konservatif yang membuat keputusan rehab satu grid lalu mengembalikannya ke normal. Hasil tersebut dicatat pada 16 Oktober 2026 di [laporan integrasi](../../docs/frontend/hackathon-integration.md); statusnya historis dan tidak diverifikasi ulang saat README ini diperbarui. Periksa kembali ketersediaan, konfigurasi backend, dan akses akun sebelum menggunakan demo hosted. Laporan tersebut juga mencatat bahwa inspeksi tampilan di browser terhalang, sehingga belum menjadi bukti render end-to-end terkini atau smoke test production terbaru.

Baris sumber ML/habitat dalam laporan itu berasal dari bulan sumber terakhir yang tersedia saat itu (2025-12), bukan observasi lingkungan terkini. Keterbatasan satuan sumber dan kamus kode habitat tetap berlaku sebagaimana dijelaskan di laporan. Aplikasi ini adalah prototipe pendukung keputusan; tidak ada dampak ekologis, hasil tangkapan, pendapatan, atau komunitas yang terukur dan diklaim.

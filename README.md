# reefish

Reefish (Tangkap & Pulih) adalah proyek JOINTS Hackathon 2026 untuk logbook nelayan dan alat bantu pengelolaan kawasan. Monorepo ini membagi pekerjaan menjadi machine learning, backend, dan frontend. Implementasi Flutter tersedia untuk Splash, Welcome, Create Account, dan Login, dengan integrasi Supabase Auth untuk nomor HP dan kata sandi, verifikasi OTP, sesi, serta logout. Login telepon live memerlukan aktivasi Phone Auth pada project Supabase.

```text
reefish/
├── machine-learning/
│   ├── notebooks/
│   ├── src/
│   ├── tests/
│   ├── data/
│   └── models/
├── backend/
│   └── supabase/
│       ├── migrations/
│       ├── functions/
│       └── tests/
├── frontend/
│   ├── mobile/          # Flutter
│   └── web/             # Next.js
├── contracts/
└── docs/
```

## Area kerja

- `machine-learning/` — eksperimen dan komponen ML dengan review manusia.
- `backend/` — migrasi, fungsi, dan pengujian backend Supabase.
- `frontend/mobile/` — aplikasi Flutter.
- `frontend/web/` — aplikasi Next.js.
- `contracts/` — definisi kontrak dan fixture lintas domain.
- `docs/` — catatan arsitektur dan keputusan yang disepakati.

Supabase adalah arah backend awal. Pemilihan library dan versi dependensi diselesaikan saat bootstrap masing-masing aplikasi. Source code dan kontrak berada di Git; kredensial, dataset, bobot model, serta artefak build disimpan di luar repo.

## Menjalankan aplikasi mobile

Project Flutter berada di `frontend/mobile/`. Dari root repository:

```powershell
cd frontend/mobile
flutter pub get
./scripts/run.ps1 -Device edge
```

Untuk preview dengan ukuran layar desain, jalankan `./scripts/preview.ps1` dari folder mobile. Preview web memerlukan Flutter SDK dan browser; Android Studio atau emulator tidak diperlukan. Build Android memerlukan Android SDK.

Implementasi memakai feature-first, Cubit untuk alur auth, serta interface repository. UI mengikuti empat frame Figma dan memakai aset lokal. Salin `config/supabase.example.json` menjadi `config/supabase.local.json` di folder mobile dan isi URL serta publishable key. Script run/preview membaca konfigurasi lokal yang diabaikan Git. Tanpa konfigurasi, aplikasi menampilkan pesan layanan belum terhubung. OTP telepon memerlukan konfigurasi provider SMS, termasuk saat memakai nomor uji.

Pemeriksaan mobile: `flutter analyze`, `flutter test`, dan `flutter build web -t tool/preview.dart --no-web-resources-cdn`. Lihat [panduan mobile](frontend/mobile/README.md) untuk setup dan batas verifikasi. Workflow GitHub Actions berada di `.github/workflows/flutter.yml` dan menjalankan pemeriksaan dari folder mobile.

## Mulai bekerja

1. Clone repo: `git clone https://github.com/Malwildan/reefish.git`.
2. Baca README pada area yang dikerjakan serta panduan kontrak bersama.
3. Buat branch untuk satu perubahan, lalu ajukan pull request ke `main`.
4. Saat aplikasi di-bootstrap, tambahkan instruksi setup, lockfile, dan perintah validasi pada README area tersebut.

Lihat [docs/architecture.md](docs/architecture.md) dan [CONTRIBUTING.md](CONTRIBUTING.md).

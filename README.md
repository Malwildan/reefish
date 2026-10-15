# reefish

Reefish (Tangkap & Pulih) adalah proyek JOINTS Hackathon 2026 untuk logbook nelayan dan alat bantu pengelolaan kawasan. Monorepo ini membagi pekerjaan menjadi machine learning, backend, dan frontend. Status: struktur awal untuk memulai development.

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

## Mulai bekerja

1. Clone repo: `git clone https://github.com/Malwildan/reefish.git`.
2. Baca README pada area yang dikerjakan serta panduan kontrak bersama.
3. Buat branch untuk satu perubahan, lalu ajukan pull request ke `main`.
4. Saat aplikasi di-bootstrap, tambahkan instruksi setup, lockfile, dan perintah validasi pada README area tersebut.

Lihat [docs/architecture.md](docs/architecture.md) dan [CONTRIBUTING.md](CONTRIBUTING.md).

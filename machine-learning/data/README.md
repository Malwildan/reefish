# Data lokal

Data lokal tidak dilacak Git. Dokumentasikan sumber, izin, cakupan, dan batas pemakaian sebelum digunakan. Jangan taruh data privat atau data lapangan tanpa persetujuan dan prosedur yang sesuai.

## Susunan

```
raw/layers/            sumber asli layer peta, jangan diubah
  potensi_ikan.csv, suhu_laut.csv, kedalaman_laut.csv   grid_x,grid_y,latitude,longitude,value (31.354 sel)
  klorofil_a.csv       24 entri per sel (752.496 baris)
  mangrove_2023_jatim.geojson
  coralreef.geojson    sumber asli coral, sama dengan coralreef(1).geojson di panduan
                       (SHA-256 62c71b6c124e2d5913d0a244cbd2544a5f4d5fc8ee8ea4fdc12204db28fce57b)
processed/             turunan hasil src/geodata_prep (audit + perbaikan geometri)
  geodata/coral.geojson, geodata/mangrove.geojson
  geodata/klorofil_a/blok_01..24.csv + manifest.json
  validation_report.json, SHA256SUMS.json
geojson/               output model cluster (clusters_YYYY-MM.geojson + metadata.json)
```

## Pemakai

- `geojson/` adalah input `backend/scripts/geojson_to_csv.py`, yang mengisi `grid_cells` dan `cluster_predictions` di Supabase.
- `processed/geodata/` adalah aset peta Flutter (`frontend/mobile/examples/peta_laut`). Salin ke `assets/geodata/` aplikasi saat build.
- `raw/layers/` adalah input `src/geodata_prep/audit_prepare.py`.

## Mengulang audit

Script butuh nama berkas persis seperti di panduan. Siapkan folder input terpisah:
- salin `coralreef.geojson` sebagai `coralreef(1).geojson`;
- salin `kedalaman_laut.csv` sekali lagi sebagai `kedalaman_laut (1).csv`;
- salin layer lain apa adanya.

Lalu, dengan venv yang memakai `src/geodata_prep/requirements.txt`, jalankan:

```sh
python src/geodata_prep/audit_prepare.py --input <folder_input> --output <folder_hasil>
```

Folder input dan folder hasil tidak boleh bersarang.

Hasil audit ulang 16-10-2026:
- `coral.geojson`, `mangrove.geojson`, ke-24 blok klorofil, dan `manifest.json` identik byte-per-byte dengan `processed/geodata/`.
- `validation_report.json` versi tersimpan memuat detail audit klorofil yang lebih lengkap daripada yang ditulis script repo. Datanya sama.

## Grid

Grid sama untuk semua layer dan untuk `grid_cells` backend:
- Proyeksi EPSG:32749, sel 500 m, origin kiri bawah (637500, 8988000).
- `grid_x` 1..187 ke timur, `grid_y` 1..177 ke utara.
- ID backend: `X{grid_x:03}_Y{grid_y:03}`.

Detail lengkap ada di `docs/frontend/panduan-implementasi-flutter-peta-laut-v2.md` bagian 7.

## Temuan audit backend (16-10-2026)

Hasil cek numerik terhadap output cluster:
- **Klorofil-a:** entri ke-n per sel sama dengan `chlor_a` periode ke-n, mulai `2024-01` sampai `2025-12`. Tidak ada selisih pada 752.496 baris. Artinya ke-24 entri adalah bulan.
- **Suhu:** `suhu_laut.csv` sama dengan `sst` periode `2025-12`.
- **Kedalaman:** `kedalaman_laut.csv` sama dengan `depth_m`, yang tetap di semua periode.
- **Potensi ikan:** `potensi_ikan.csv` tidak cocok dengan `potential_score` periode yang dicek (2024-01, 2025-12). Anggap dataset terpisah sampai pemilik data menjelaskan.

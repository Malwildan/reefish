# Paket handoff peta laut Flutter — revisi 2 + klorofil-a

Baca `docs/frontend/panduan-implementasi-flutter-peta-laut-v2.md` untuk audit, asumsi, dan langkah integrasi lengkap.

## Integrasi

1. Gunakan Flutter stable dengan Dart >=3.10.1.
2. Buat proyek terpisah: `flutter create marine_map_demo`.
3. Salin `lib/` dan `pubspec.yaml` dari folder ini ke proyek tersebut. Aset data tidak dilacak Git, jadi salin dari `machine-learning/data/processed/geodata/` dan `machine-learning/data/raw/layers/`. Dari root repo:

   ```sh
   mkdir -p marine_map_demo/assets/geodata
   cp -r machine-learning/data/processed/geodata/. marine_map_demo/assets/geodata/
   cp machine-learning/data/raw/layers/{potensi_ikan,suhu_laut,kedalaman_laut}.csv marine_map_demo/assets/geodata/
   ```

4. Ubah identitas aplikasi pada TileLayer dan pastikan permission Internet pada Android release.
5. Jalankan `flutter pub get`, `dart format lib`, `flutter analyze`, lalu `flutter run`.

Kode Flutter belum dikompilasi atau diuji perangkat di lingkungan pembuat paket. Paket ini merupakan contoh integrasi, bukan build aplikasi siap rilis. Data sudah diaudit secara numerik/spasial.

## Aset

Tiga CSV dasar adalah salinan asli. Klorofil-a dipisah tanpa agregasi menjadi 24 bagian CSV, masing-masing 31.354 sel, pada assets/geodata/klorofil_a/. Seluruh 752.496 baris dipertahankan. Nomor entri menyatakan urutan ekspor, bukan waktu; satu nilai final per sel belum ditetapkan. Layer pratinjau nonaktif secara default. Coral merupakan hasil make_valid + clip AOI; seluruh kelas 0 dan 1 disimpan, dengan filter kode 1 sementara pada renderer. Mangrove dinormalisasi dan diberi ID lokal. Lihat `validation_report.json` untuk audit sumber dan log transformasi.

Satuan dan waktu CSV serta arti kelas belum dikonfirmasi. Pemilik menyebut klorofil sebagai ekspor XY/lat/long/value, tanpa dimensi pembeda bagi 24 entri per sel. Jangan menimpa nilai duplikat atau merata-ratakan otomatis. Jangan memberi label %, °C, atau meter pada nilai observasi sampai metadata tersedia. Grid 500 m menggunakan EPSG:32749, origin (637500,8988000).

## Mengulang audit dari tujuh sumber asli

Gunakan Python 3.12 dan folder input berisi nama berkas asli persis seperti pada panduan. Simpan input dan hasil pada folder terpisah yang tidak saling bersarang.

Script ada di `machine-learning/src/geodata_prep/`:

```sh
python -m pip install -r machine-learning/src/geodata_prep/requirements.txt
python machine-learning/src/geodata_prep/audit_prepare.py --input /path/ke/sumber_asli --output /path/ke/hasil_audit
```

Script menulis `assets/geodata/` dan `validation_report.json` pada folder hasil; tidak mengubah berkas input. GeoJSON hasil perbaikan perlu ditinjau secara visual oleh tim data sebelum rilis.

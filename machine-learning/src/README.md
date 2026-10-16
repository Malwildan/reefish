# Kode sumber ML dan geodata

Kode yang benar-benar tersedia saat ini berada di `geodata_prep/`. Isinya merupakan utilitas audit dan persiapan data geospasial, bukan kode pelatihan atau inferensi model.

## Yang dilakukan

- [`geodata_prep/audit_prepare.py`](geodata_prep/audit_prepare.py) memeriksa schema dan nilai CSV, indeks/koordinat grid, cakupan area, geometri GeoJSON, dan keselarasan beberapa layer. Ia membuat laporan validasi serta aset turunan untuk peta. Laporan membatasi cakupannya pada pemeriksaan struktural, numerik, topologi, dan spasial; provenance ilmiah dan unit nilai belum diverifikasi.
- [`geodata_prep/prepare_chlorophyll.py`](geodata_prep/prepare_chlorophyll.py) memvalidasi 24 blok lengkap, urutan key dan koordinat terhadap referensi 31.354 sel, lalu menulis tiap blok dan manifest hash. Label blok adalah urutan berkas sumber; waktu, unit, dan arti pengukuran belum diverifikasi.
- [`geodata_prep/requirements.txt`](geodata_prep/requirements.txt) mencatat dependensi utilitas geodata.

## Penggunaan audit

Dari root repository, ikuti daftar nama berkas serta aturan folder input/output di [`../data/README.md`](../data/README.md), siapkan lingkungan dengan dependensi `machine-learning/src/geodata_prep/requirements.txt`, lalu jalankan:

```sh
python machine-learning/src/geodata_prep/audit_prepare.py --input <folder_input> --output <folder_hasil>
```

Script menolak folder input dan output yang bersarang. Untuk persiapan klorofil mandiri dari root repository:

```sh
python machine-learning/src/geodata_prep/prepare_chlorophyll.py --input <klorofil_a.csv> --reference <potensi_ikan.csv> --output <folder_hasil>
```

## Batas dan bukti demonstrasi

Jangan menyebut audit sebagai validasi ilmiah, perbaikan sebagai pembuktian akurasi, atau aset peta sebagai hasil inferensi model. Demo yang dapat direproduksi perlu menyertakan versi Python/dependensi, hash sumber, laporan, dan ringkasan jumlah fitur/baris; gunakan salinan data berizin yang tidak dimasukkan ke Git. Belum ada modul pelatihan, API prediksi, atau metrik model di folder ini.

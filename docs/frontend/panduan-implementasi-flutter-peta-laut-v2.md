# Panduan handoff implementasi peta laut di Flutter — revisi 2, tambahan klorofil-a

**Bahasa:** Indonesia • **Audit berkas dan pemeriksaan dokumentasi:** 16 Oktober 2026

Dokumen ini disusun dari pemeriksaan langsung enam unggahan awal dan satu berkas tambahan `klorofil_a.csv` pada percakapan **Panduan Implementasi Flutter**. Angka pada bagian audit adalah hasil pembacaan berkas, bukan contoh buatan. Rekomendasi style dan keputusan implementasi ditandai terpisah dari fakta data.

**Keputusan implementasi:** gunakan `flutter_map` untuk peta dan layer vektor, pertahankan satu identitas sel `(grid_x, grid_y)` untuk ketiga CSV, dan rekonstruksi grid 500 m pada UTM zona 49 selatan. Gunakan GeoJSON yang telah diperbaiki untuk coral. Tampilan peta memakai Web Mercator, sementara perhitungan ukuran grid memakai meter dalam UTM.

Paket pendamping `Flutter_Map_Handoff_v2.zip` berisi kode Dart, lima aset dasar serta 24 bagian ekspor klorofil-a, dan `validation_report.json`. Kode merupakan contoh integrasi yang dapat dipindahkan ke proyek Flutter; folder platform Android/iOS/web dibuat dengan `flutter create`. Pemeriksaan data sudah dijalankan. **Kode Flutter belum dikompilasi atau diuji pada perangkat dalam lingkungan penyusunan ini karena Flutter/Dart SDK tidak tersedia.**

> **Catatan repo reefish (16-10-2026):**
> - **Lokasi berkas:**
>   - Contoh kode ada di `frontend/mobile/examples/peta_laut/`.
>   - Script audit ada di `machine-learning/src/geodata_prep/`.
>   - Data ada di `machine-learning/data/raw/layers/` dan `machine-learning/data/processed/`. Data tidak dilacak Git.
> - **Temuan audit backend:**
>   - Entri klorofil ke-n sama persis dengan `chlor_a` output cluster ML periode `2024-01` + (n−1) bulan, tanpa selisih pada seluruh 752.496 baris. Dimensi entri yang disebut "belum diketahui" di bagian 19 kemungkinan besar adalah bulan 2024-01…2025-12.
>   - `suhu_laut.csv` sama dengan `sst` periode 2025-12.
>   - Kedalaman tetap di semua periode.
>   - Konfirmasi tetap ke pemilik data sebelum label bulan dipakai di UI.

## 1. Ringkasan yang perlu diketahui frontend

1. Tujuh berkas sumber berisi **enam dataset unik** (lima dataset awal dan klorofil-a). Dua CSV kedalaman identik secara byte dan hash; gunakan satu saja.
2. Tiga dataset numerik dasar masing-masing berisi **31.354 sel**, dengan pasangan indeks, urutan baris, dan koordinat yang sama persis. Tetap lakukan join berdasarkan indeks agar aman jika urutan ekspor berubah.
3. Koordinat CSV konsisten dengan pusat grid **500 × 500 meter dalam EPSG:32749**. Ini hasil inferensi numerik yang sangat kuat, bukan CRS yang tertulis di CSV.
4. Coral terdiri atas **116 fitur berkode `1.0` dan 24 berkode `0.0`**. Jangan mewarnai seluruh fitur sebagai coral. Berkas tidak menyertakan kamus kelas; contoh sementara menampilkan kode 1 saja dan menyebutkan asumsi tersebut.
5. Ada **13 geometri coral tidak valid** dan **16 fitur coral tidak seluruhnya berada dalam bounds**. Paket menyediakan versi turunan hasil perbaikan dan pemotongan. Mangrove valid dan berada di dalam area.
6. Klorofil-a mempunyai 24 entri berbeda per sel tanpa kolom pembeda. Pemilik menyatakan ini ekspor XY/latitude/longitude/value, bukan memberikan pemetaan bulan. Contoh hanya menyediakan pratinjau urutan entri, bukan memilih nilai final.
7. Satuan, waktu observasi, metode, sumber ilmiah, dan aturan NoData seluruh dataset CSV tidak tersimpan di berkas. Nilai suhu tampak sesuai kisaran °C dan kedalaman tampak seperti meter, tetapi itu belum membuktikan satuannya. Nilai ikan `1–100` belum membuktikan persentase atau probabilitas.

## 2. Batas area, tanda koordinat, dan CRS

### Batas area kerja / AOI

| Arah | Batas | Nilai untuk kode |
|---|---|---:|
| Barat | 112,25° BT | longitude `112.25` |
| Timur | 113,10° BT | longitude `113.10` |
| Utara | 8,35° LS | latitude `-8.35` |
| Selatan | 9,15° LS | latitude `-9.15` |

- Bbox urutan GeoJSON/API: **`[112.25, -9.15, 113.10, -8.35]`**, yaitu `[west, south, east, north]`.
- Sudut barat daya di Dart: `LatLng(-9.15, 112.25)`.
- Sudut timur laut di Dart: `LatLng(-8.35, 113.10)`.
- Titik tengah geografis: `LatLng(-8.75, 112.675)`; gunakan fit bounds agar semua area terlihat pada beragam ukuran layar.
- Lintang selatan selalu negatif. `-8.35` berada lebih utara daripada `-9.15`.

### Konsep koordinat yang berbeda

| Kegunaan | Referensi | Urutan |
|---|---|---|
| Penyimpanan GeoJSON | WGS84 longitude/latitude, sesuai CRS84 | `[longitude, latitude]` |
| Model koordinat Flutter | WGS84 derajat | `LatLng(latitude, longitude)` |
| Hitungan ukuran dan identitas grid | WGS84 / UTM 49S, EPSG:32749 | `(Easting, Northing)` dalam meter |
| Peta dasar raster standar | EPSG:3857 / Web Mercator | ditangani `flutter_map` |

Coral menyebut `urn:ogc:def:crs:OGC:1.3:CRS84`. Mangrove tidak menyertakan anggota `crs`, tetapi koordinatnya konsisten dengan format longitude/latitude GeoJSON. CSV tidak memiliki deklarasi CRS; asumsi WGS84 pada kode didukung kesesuaian grid tetapi tetap perlu metadata sumber. CRS84 dan WGS84 geografis menggunakan datum yang sama untuk kebutuhan ini; urutan sumbu formal EPSG:4326 pada beberapa layanan dapat berbeda. Untuk GeoJSON, selalu baca longitude dahulu. [RFC 7946](https://www.rfc-editor.org/rfc/rfc7946)

Jangan mengubah semua koordinat menjadi UTM lalu memasukkannya ke `LatLng`. Jangan membuat grid dengan menambahkan `0.0045` derajat atau menggunakan sel 500 unit Web Mercator: ukuran dan keselarasan terhadap data akan berubah. Definisi UTM selatan memerlukan `+south`. [Dokumentasi PROJ UTM](https://proj.org/en/stable/operations/projections/utm.html)

## 3. Inventaris dan schema aktual

Jumlah baris di bawah **tidak termasuk header**. Ukuran memakai byte asli.

| Berkas asli | Ukuran | Isi | Schema utama |
|---|---:|---|---|
| `coralreef(1).geojson` | 579.630 | 140 fitur `Polygon` | `properties.value`: angka pecahan |
| `potensi_ikan.csv` | 1.112.115 | 31.354 baris | `grid_x,grid_y,latitude,longitude,value` |
| `suhu_laut.csv` | 1.143.292 | 31.354 baris | schema sama |
| `kedalaman_laut.csv` | 1.135.689 | 31.354 baris | schema sama |
| `kedalaman_laut (1).csv` | 1.135.689 | duplikat identik | jangan dimuat sebagai layer tambahan |
| `mangrove_2023_jatim.geojson` | 6.919 | 3 fitur `Polygon` | `area_clip_km2`, `area_km2`, `gridcode`, `year` |
| `klorofil_a.csv` | 28.188.684 | **752.496 baris, 24 entri per sel** | schema CSV sama, tetapi key sel berulang |

Semua berkas dapat dibaca sebagai UTF-8 dan tidak memakai BOM. CSV dipisahkan koma, memakai titik desimal, dan semua field numeriknya terisi serta finite. Tidak ditemukan indeks pecahan, duplikasi pasangan grid, atau duplikasi pasangan koordinat di masing-masing dari tiga CSV dasar. Klorofil-a memiliki multiplicity berbeda; lihat bagian 19.

### CSV dasar: model kontrak

```text
grid_x    integer, 1..187
grid_y    integer, 1..177
latitude  double, derajat selatan bertanda negatif
longitude double, derajat timur bertanda positif
value     double, arti berbeda menurut dataset
```

Contoh asli yang sama pada ketiga dataset:

```csv
# potensi_ikan.csv — komentar ini bukan bagian berkas asli
grid_x,grid_y,latitude,longitude,value
149,1,-9.14772,112.9269473,16.35
150,1,-9.1476958,112.9314956,18.43
151,1,-9.1476715,112.9360439,17.16
```

Pada sel `(149,1)`: ikan `16.35`, suhu `29.136`, kedalaman `5000.0`.

### Coral: schema dan batas interpretasi

```json
{
  "type": "Feature",
  "properties": {"value": 1.0},
  "geometry": {"type": "Polygon", "coordinates": ["ring luar, lalu holes"]}
}
```

Fragmen di atas hanya menjelaskan struktur, bukan GeoJSON siap dimuat. Satu-satunya atribut asli adalah `value`; tidak ada nama, tingkat kesehatan, tutupan persen, tahun, atau ID stabil. Ada **160 interior ring/holes** dan **12.580 vertex** pada berkas asli, termasuk vertex penutup ring. Semua ring tertutup. Ring tertutup tidak otomatis berarti topologi valid.

Kode 0 mencakup area yang jauh lebih luas daripada kode 1, sehingga mewarnai semuanya dapat membuat seluruh wilayah tampak sebagai coral. Contoh UI memilih `value == 1.0` dengan label sementara. Jangan menyebut kode 0 sebagai daratan atau laut kosong tanpa kamus kelas.

### Mangrove: schema dan nilai aktual

| Atribut | Tipe aktual | Isi |
|---|---|---|
| `gridcode` | integer | `1` pada seluruh 3 fitur |
| `year` | integer | `2023` pada seluruh 3 fitur |
| `area_km2` | double | `0.062803`, `0.157459`, `0.179565` |
| `area_clip_km2` | double | sekitar `0.06308458`, `0.15808557`, `0.18025207` |

Terdapat **2 holes dan 159 vertex**. Nama berkas menyebut Jatim, tetapi unggahan ini hanya berisi tiga polygon lokal; jangan menyatakan cakupannya seluruh Jawa Timur. `area_clip_km2` sedikit lebih besar daripada `area_km2` di ketiga fitur. Pertahankan kedua atribut sebagai nilai sumber; jangan menyimpulkan salah satunya luas hasil hitung yang lebih akurat atau menjumlahkannya bersama. Jika perlu luas baru, hitung di CRS metrik/geodesik dan beri atribut berbeda beserta metode.

## 4. Cakupan koordinat aktual

Urutan rentang tabel: longitude barat–timur, kemudian latitude selatan–utara. Angka dibulatkan di tabel; JSON audit menyimpan presisi hasil pembacaan.

| Dataset | Rentang longitude | Rentang latitude | Hubungan dengan AOI |
|---|---|---|---|
| Coral seluruh kelas | `112.249884642 .. 113.100140059` | `-9.150329316 .. -8.349930397` | sedikit melewati keempat sisi |
| Coral khusus kode 1 | `112.261742404 .. 112.872147640` | `-8.464465596 .. -8.349930397` | sebagian menyentuh/melewati utara |
| Ikan, suhu, kedalaman — pusat sel | `112.252288 .. 113.0976959` | `-9.14772 .. -8.3544645` | seluruh pusat berada di dalam AOI |
| Klorofil-a | `112.252288 .. 113.0976959` | `-9.14772 .. -8.3544645` | sama persis dengan pusat grid CSV dasar |
| Mangrove | `112.660057120 .. 112.716380387` | `-8.440569553 .. -8.414160051` | seluruh geometri di dalam AOI |

Semua 140 fitur coral beririsan dengan AOI; hanya 124 yang seluruhnya berada di dalamnya. Kelebihan koordinat coral berada pada skala beberapa sampai puluhan meter. Cakupan bbox seluruh kelas coral tidak boleh dijadikan ukuran cakupan coral kode 1.

Tiga CSV dasar dan klorofil-a mempunyai bbox yang sama dan **tidak menutup setiap posisi dalam AOI**. Rentang indeks membentuk persegi panjang konseptual `187 × 177 = 33.099` posisi, sedangkan hanya 31.354 tersedia; **1.745 pasangan indeks tidak disediakan**. Sel hilang bukan nilai nol dan bukan bukti daratan. Identitas yang tidak tersedia harus menghasilkan “Tidak ada data”.

Audit juga merekonstruksi keempat sudut untuk seluruh 31.354 sel yang tersedia. **Semua footprint sel berada di dalam AOI**; pada snapshot ini tidak ada sel tersedia yang perlu dipotong. Ini pemeriksaan footprint, bukan hanya pusat titik. Untuk ekspor baru, ulangi pemeriksaan ini sebelum mempertahankan asumsi tersebut.

## 5. Nilai aktual dan informasi yang belum ada

| Dataset | Minimum | Kuartil 1 | Median | Kuartil 3 | Maksimum |
|---|---:|---:|---:|---:|---:|
| Potensi ikan | 1 | 37.30 | 56.64 | 75.0775 | 100 |
| Suhu laut | 27.964 | 28.950 | 29.146 | 29.345 | 30.391 |
| Kedalaman | 18 | 748.125 | 1840.45 | 3347.375 | 5000 |
| Klorofil-a, seluruh entri | 0.0998 | 0.4569 | 0.7177 | 1.1467 | 5.1405 |

Tidak ada nilai negatif, nol, kosong, NaN, atau infinity pada seluruh CSV yang diperiksa, termasuk klorofil-a. Hal tersebut tidak membuktikan bahwa semua nilai memiliki validitas ilmiah.

Kedalaman `5000.0` muncul **1.093 kali, sekitar 3,49%**. Belum diketahui apakah angka itu kedalaman nyata, batas pemotongan model, atau kode khusus. **Jangan otomatis menganggap 5000 sebagai NoData atau mengubahnya menjadi “≥5000 m”.** Gunakan angka sumber sampai kontrak data menjelaskan artinya.

Metadata yang perlu diminta kepada pemilik data sebelum label produk difinalisasi:

- Arti dan unit ikan: skor, probabilitas, persentase, hasil estimasi, atau besaran lain; apakah makin besar berarti makin potensial.
- Unit suhu, apakah suhu permukaan atau lapisan tertentu, kedalaman pengamatan, serta waktu/periode observasi.
- Unit kedalaman, konvensi tanda, datum vertikal, sumber, serta arti nilai 5000.
- Kamus kelas coral `0/1`, arti `gridcode` mangrove, tahun coral, dan metode pemetaan.
- Sumber/provenance, lisensi, resolusi asli, ketidakpastian, dan aturan NoData.
- Konfirmasi CRS/origin grid. Kesesuaian geometri grid 500 m tidak membuktikan resolusi pengamatan asli juga 500 m.

Implementasi dapat berjalan sambil menunggu metadata. UI contoh memakai label “nilai” dan menampilkan catatan bahwa satuan belum dikonfirmasi. Tidak ada time slider untuk CSV karena kolom waktu memang tidak ada; tahun 2023 hanya berlaku pada dataset mangrove.

## 6. Perbaikan geometri dan aset pendamping

Indeks fitur coral tidak valid, **berbasis nol**:

```text
10, 15, 38, 47, 60, 75, 92, 96, 99, 106, 125, 128, 139
```

Dua belas dilaporkan sebagai ring self-intersection, satu sebagai interior disconnected. Hal ini berisiko menghasilkan isian salah, holes tertutup, atau kegagalan triangulasi. Jangan mengandalkan renderer untuk memperbaikinya.

Pipeline aset turunan yang sudah dijalankan:

1. Baca geometri dan periksa validitas topologi.
2. Untuk fitur invalid, jalankan `make_valid` metode default `linework`.
3. Intersect geometri hasil perbaikan dengan polygon AOI dalam longitude/latitude.
4. Ambil bagian berjenis polygon; komponen garis/titik hasil keruntuhan topologi tidak dirender sebagai area.
5. Pertahankan properties sumber dan tambahkan `source_feature_index` serta ID fitur lokal.
6. Normalisasi orientasi ring, ekspor GeoJSON tanpa anggota `crs` lama, lalu periksa kembali validitas dan containment AOI.

Perbaikan bisa mengubah `Polygon` menjadi `MultiPolygon` atau koleksi geometri; karena itu parser harus menangani MultiPolygon. Perubahan merupakan normalisasi geometrik, bukan verifikasi batas habitat oleh ahli. Bandingkan tampilan hasil perbaikan dengan sumber sebelum rilis. [Dokumentasi Shapely make_valid](https://shapely.readthedocs.io/en/stable/reference/shapely.make_valid.html)

| Aset di ZIP | Isi/transformasi |
|---|---|
| `assets/geodata/coral.geojson` | 140 fitur tetap dipertahankan: **127 Polygon + 13 MultiPolygon**, seluruhnya valid dan berada dalam AOI; kelas 0 dan 1 tetap ada |
| `assets/geodata/mangrove.geojson` | 3 Polygon valid; properti dan holes dipertahankan; diberi ID lokal |
| `assets/geodata/potensi_ikan.csv` | salinan byte asli |
| `assets/geodata/suhu_laut.csv` | salinan byte asli |
| `assets/geodata/kedalaman_laut.csv` | salinan byte asli; salinan duplikat tidak disertakan lagi |
| `assets/geodata/klorofil_a/blok_01.csv` … `blok_24.csv` | split tanpa agregasi dari klorofil-a; setiap bagian 31.354 key unik |
| `assets/geodata/klorofil_a/manifest.json` | batas baris sumber, hash per bagian, rentang nilai, unit/waktu null |
| `validation_report.json` | ukuran/hash sumber, schema, rentang, daftar geometri invalid, keselarasan CSV, hasil fit grid, log perubahan aset |

Berkas asli tidak ditimpa. ID berbasis indeks sumber hanya stabil untuk snapshot ini; untuk pembaruan data gunakan ID dari penerbit atau prosedur ID yang konsisten antarversi.

## 7. Definisi grid 500 × 500 meter yang cocok dengan data

Hasil transformasi seluruh pusat ke EPSG:32749 mengikuti:

```text
E_center = 637250 + 500 × grid_x
N_center = 8987750 + 500 × grid_y
```

Bentuk lain dengan origin sudut kiri bawah sel `(1,1)`:

```text
origin_E = 637500 meter
origin_N = 8988000 meter
cell_size = 500 meter

E_center = origin_E + (grid_x - 0.5) × cell_size
N_center = origin_N + (grid_y - 0.5) × cell_size

E_left   = origin_E + (grid_x - 1) × cell_size
E_right  = E_left + cell_size
N_bottom = origin_N + (grid_y - 1) × cell_size
N_top    = N_bottom + cell_size
```

`grid_x` bertambah ke timur dan `grid_y` bertambah ke utara. Jadi baris y=1 berada di sisi selatan, bukan di utara.

Keempat sudut sel dihitung dalam UTM, kemudian ditransformasikan kembali ke WGS84 untuk dirender. Bentuknya dapat sedikit miring terhadap sumbu longitude/latitude; ini sesuai grid data. Sel berukuran 500 × 500 **meter proyeksi UTM**, dengan luas nominal 250.000 m² = 0,25 km² sebelum clipping. Ukuran tanah/geodesik dapat sedikit berbeda karena faktor skala proyeksi.

Bukti numerik hasil audit:

- Jarak tetangga arah x: **31.148 pasangan**, rentang `499.989052 .. 500.011019 m`, median sekitar 500 m.
- Jarak tetangga arah y: **31.166 pasangan**, rentang `499.989017 .. 500.011024 m`, median sekitar 500 m.
- Selisih maksimum per sumbu terhadap rumus integer di atas: **0,005554 m** setelah pembulatan ke atas; konsisten dengan koordinat CSV yang dibulatkan.
- Origin dan arah merupakan hasil inferensi dari semua titik. Simpan sebagai metadata kontrak versi data, jangan menghitung ulang origin dari minimum longitude setiap kali layer dinyalakan.

Contoh sel `(149,1)`:

```text
Pusat UTM: E=711750, N=8988250
SW [lon,lat]: [112.9246853312, -9.1499920277]
SE [lon,lat]: [112.9292336427, -9.1499678453]
NE [lon,lat]: [112.9292092861, -9.1454479164]
NW [lon,lat]: [112.9246610319, -9.1454720866]
```

Grid default pada contoh hanya menggambar sel yang tersedia di CSV. Jika produk membutuhkan grid latar untuk **seluruh AOI**, buat layer referensi terpisah dengan origin yang sama, perluas rentang indeks hingga mencakup AOI, lalu clip ke polygon AOI. Sel referensi tanpa observasi tetap tidak memiliki nilai. Jangan mengisi data baru dengan nol atau menyalin nilai tetangga.

Untuk ekspor baru dengan sel yang memotong batas: clip polygon sel dengan polygon AOI pada tahap persiapan data. Jangan membatasi setiap vertex dengan `clamp`: operasi itu dapat merusak geometri. Sel tepi setelah clipping bukan lagi sel penuh 0,25 km².

## 8. Urutan, toggle, dan opacity

Urutan berikut ditafsirkan **dari bawah ke atas**, mengikuti permintaan awal. Child yang ditambahkan terakhir berada di atas layer sebelumnya.

| Posisi | Layer | Bentuk | Default contoh |
|---:|---|---|---|
| 1 | Base map | raster `TileLayer` | aktif |
| 2 | Coral | `PolygonLayer`, kode 1 sementara | aktif, alpha 0,55 |
| 3 | Potensi ikan | isian polygon sel | aktif, alpha 0,55 |
| 3a (tambahan) | Klorofil-a | isian polygon sel, pratinjau entri 1–24 | **nonaktif**, alpha 0,55 |
| 4 | Mangrove | `PolygonLayer` | aktif, alpha 0,55 |
| 5 | Suhu laut | isian polygon sel | nonaktif |
| 6 | Kedalaman laut | isian polygon sel | nonaktif |
| 7 | Grid 500 m | garis sisi sel, tanpa fill | aktif, tampil pada zoom ≥12 |

Urutan disimpan sebagai daftar tetap/enum, terpisah dari status aktif. Toggle hanya mengubah visibility; jangan menambah ulang layer pada akhir daftar karena akan mengubah z-order. Jika kemudian ada fitur drag reorder, simpan daftar urutan secara eksplisit.

Keempat layer numerik (termasuk klorofil-a opsional) memakai sel yang sama. Jika semuanya aktif dan opak, kedalaman akan menyembunyikan suhu dan ikan. Transparansi juga mencampurkan warna, sehingga legenda warna tiap variabel tidak lagi bisa dibaca secara mandiri. UX yang disarankan untuk produksi adalah pilihan cepat satu layer numerik, sambil tetap menyediakan mode perbandingan dengan toggle dan opacity. Contoh kode menyediakan toggle mandiri sesuai permintaan.

Karena urutan diminta menempatkan coral di bawah ikan, coral dapat tertutup. Turunkan opacity ikan atau matikan layer numerik saat meninjau habitat. Mengangkat coral ke atas semua layer adalah perubahan keputusan produk, bukan efek samping toggle.

Grid harus mengabaikan pointer agar tidak menghalangi tap data. Tooltip angka sebaiknya menampilkan **semua nilai sel yang sama**, bukan hanya nilai dari polygon paling atas.

## 9. Pilihan package dan struktur yang mudah dirawat

Paket pendamping menggunakan versi eksplisit yang diperiksa pada tanggal dokumen:

```yaml
environment:
  sdk: '>=3.10.1 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  flutter_map: 8.3.2
  latlong2: 0.10.1
  csv: 8.0.0
  proj4dart: 3.0.0
flutter:
  uses-material-design: true
  assets:
    - assets/geodata/
    - assets/geodata/klorofil_a/
```

`flutter_map` menangani base map dan layer vektor; `latlong2` menyimpan LatLng; `csv` menangani quoted fields/newline; `proj4dart` melakukan transformasi grid. Gunakan stable Flutter yang membawa Dart minimal 3.10.1 untuk konfigurasi ini; batas SDK terutama mengikuti `csv 8.0.0`. Setelah `flutter pub get`, simpan `pubspec.lock` aplikasi. Hindari `dependency_overrides` untuk memaksa kombinasi yang belum kompatibel. [flutter_map](https://pub.dev/packages/flutter_map), [latlong2](https://pub.dev/packages/latlong2), [csv](https://pub.dev/packages/csv), [proj4dart](https://pub.dev/packages/proj4dart)

Contoh ini tidak memerlukan plugin GeoJSON tambahan: schema kecil dapat diparsing langsung dengan `dart:convert`. Hal ini membuat dukungan holes, MultiPolygon, validasi, dan konversi sumbu terlihat jelas. Sesuaikan state management dengan proyek yang sudah ada; `StatefulWidget` cukup untuk contoh, lalu pisahkan state layer ke controller/ChangeNotifier bila halaman bertambah.

```text
lib/
  geodata.dart          # DTO, parser ketat, join berdasarkan GridId
  grid_projection.dart  # origin, transformasi, cache vertex, hit lookup
  map_layers.dart       # style dan konversi model menjadi polygon/garis
  chlorophyll_repository.dart # lazy load satu entri, cache maksimal 2
  main.dart             # pemuatan asset, kamera, toggle, opacity, panel nilai
assets/geodata/
  coral.geojson
  mangrove.geojson
  potensi_ikan.csv
  suhu_laut.csv
  kedalaman_laut.csv
  klorofil_a/
    blok_01.csv ... blok_24.csv
    manifest.json
validation_report.json
```

Pada proyek produksi, repository bertanggung jawab pada load/cache/versioning; parser hanya mengubah teks menjadi model; controller menyimpan status loading/error/layer; renderer membaca model dan style. Jangan melakukan pembacaan berkas, join, atau transformasi massal di `build()`.

## 10. Langkah menjalankan contoh

1. Ekstrak ZIP. Buat proyek baru pada direktori terpisah agar tidak menimpa proyek frontend yang sudah ada:

   ```sh
   flutter create marine_map_demo
   ```

2. Salin direktori `lib/`, `assets/`, dan `pubspec.yaml` dari paket ke proyek baru itu. Pada proyek existing, gabungkan dependency dan asset ke pubspec existing, lalu pindahkan halaman dan modul dengan namespace yang sesuai.
3. Ubah `userAgentPackageName` dari `id.example.marine_map_handoff` menjadi identitas aplikasi yang sebenarnya. Atur base map lewat konfigurasi environment pada integrasi produksi.
4. Pastikan manifest Android utama memiliki permission Internet untuk build release:

   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```

5. Jalankan:

   ```sh
   flutter pub get
   dart format lib
   flutter analyze
   flutter run
   ```

6. Uji profile mode pada perangkat target; untuk pengukuran rendering jangan memakai debug mode.

Base map contoh memakai OSM standar untuk melihat integrasi. Attribution harus tetap terlihat, identitas request aplikasi harus benar, caching mengikuti header, dan server publik OSM tidak boleh dipakai untuk bulk download atau fitur unduh offline. Untuk kebutuhan trafik/SLA/offline, pilih penyedia dengan ketentuan yang sesuai atau hosting sendiri. [Kebijakan tile OSM](https://operations.osmfoundation.org/policies/tiles/)

`flutter_map` 8.2+ memiliki caching dasar otomatis pada platform non-web; web memakai cache browser. Cache ini dapat dibersihkan sistem dan tidak menjamin ketersediaan offline. Pisahkan cache tile peta dari cache dataset milik aplikasi. [Dokumentasi caching flutter_map](https://docs.fleaflet.dev/layers/tile-layer/caching)

## 11. Parsing, join, dan penanganan error

Untuk tiga CSV dasar dan setiap bagian klorofil yang sudah dipisah:

1. Baca sekali lewat asset repository. Hilangkan BOM bila ada pada ekspor mendatang.
2. Gunakan parser CSV, bukan `split(',')`/`split('\n')` manual.
3. Cocokkan kolom berdasarkan nama, bukan asumsi posisi kolom.
4. Parse angka menggunakan `num`/`double.tryParse`, pastikan finite, dan validasi grid integer serta koordinat AOI.
5. Tolak ID ganda. Jangan diam-diam menimpa nilai terakhir.
6. Join berdasarkan `(grid_x, grid_y)`. Verifikasi koordinat join juga selaras; contoh menggunakan toleransi `1e-7` derajat.
7. Jangan mengubah nilai yang gagal diparse menjadi `0`. Laporkan nama berkas/baris/kolom dan tampilkan status gagal layer.

Contoh parser mengunci jumlah 31.354 dan rentang indeks snapshot agar perubahan data tidak lolos tanpa disadari. Saat menggunakan dataset baru, ubah manifest versi dan batas validasinya secara sadar. Untuk kontrak pembaruan yang memperbolehkan key berbeda, lakukan outer join dan simpan `double?` per variabel; tampilkan NoData secara transparan. Jangan memakai inner join tanpa melaporkan sel yang hilang.

Untuk GeoJSON: bedakan Polygon (`[ring luar, holes...]`) dari MultiPolygon (`[polygon1, polygon2...]`). Pertahankan holes sebagai `holePointsList`. Jangan menggabungkan semua ring menjadi satu daftar titik. Parser contoh mewajibkan aset yang sudah dinormalisasi ke AOI; jika memasukkan coral asli langsung, validasi batas memang akan menolaknya. [API Polygon](https://pub.dev/documentation/flutter_map/latest/flutter_map/Polygon/Polygon.html)

Gunakan `compute()` untuk parsing numerik/JSON pada mobile dan desktop bila pekerjaan menghambat UI. Muat asset melalui `rootBundle` di isolate utama, lalu kirim string ke fungsi top-level. Jangan membuat widget atau memakai `dart:ui` di worker. Pada Flutter web, `compute()` tidak memindahkan pekerjaan ke isolate terpisah; untuk data yang berkembang gunakan preprocessing, chunking, Web Worker, atau tile. [Dokumentasi Flutter isolates](https://docs.flutter.dev/perf/isolates)

## 12. Kamera, clipping data, dan area di luar bounds

```dart
final bounds = LatLngBounds(
  const LatLng(-9.15, 112.25),
  const LatLng(-8.35, 113.10),
);

MapOptions(
  initialCameraFit: CameraFit.bounds(
    bounds: bounds,
    padding: const EdgeInsets.all(24),
  ),
  cameraConstraint: CameraConstraint.containCenter(bounds: bounds),
  minZoom: 7,
  maxZoom: 18,
)
```

`containCenter` membatasi pusat kamera. Pinggir layar masih dapat menampilkan area di luar AOI, terutama pada layar lebar. Ini sengaja dipilih agar seluruh AOI bisa ditampilkan dengan fit bounds. **Constraint kamera tidak memotong geometri.** Clipping data dilakukan saat persiapan aset. [API camera constraint](https://pub.dev/documentation/flutter_map/latest/flutter_map/CameraConstraint-class.html), [API CameraFit.bounds](https://pub.dev/documentation/flutter_map/latest/flutter_map/CameraFit/CameraFit.bounds.html)

Jika requirement produk mewajibkan seluruh viewport berada dalam AOI, gunakan `CameraConstraint.contain(bounds: bounds)` dan hitung minimum zoom sesuai ukuran viewport; fit seluruh AOI dengan padding bisa bertentangan dengan aturan tersebut. Jika requirement hanya mengosongkan area luar AOI, tambahkan mask visual di luar polygon AOI. `tileBounds` mengurangi permintaan tile tertentu; ia bukan alat clipping presisi untuk overlay data.

## 13. Rendering dan legenda

- Coral: warna oranye, holes transparan, hanya kode yang dipilih. Label kode sementara tetap terlihat sampai kamus kelas tersedia.
- Mangrove: hijau, tahun 2023 pada panel detail; tidak menambahkan marker untuk setiap vertex.
- CSV: isian sel asli 500 m sebagai choropleth. CSV tidak membawa boundary polygon; footprint dihasilkan dari grid hasil audit, bukan sebaran titik bebas.
- Grid: garis abu tipis tanpa fill, hanya saat ukuran sel terbaca; contoh memakai ambang zoom 12 sebagai parameter UX yang dapat disetel.

Style contoh memakai interpolasi warna berdasarkan rentang snapshot:

| Layer | Warna rendah → tinggi | Rentang visual |
|---|---|---|
| Ikan | kuning muda → hijau | 1–100 |
| Suhu | biru → merah | 27.964–30.391 |
| Kedalaman | biru muda → biru tua | 18–5000 |
| Klorofil-a, pratinjau | kuning muda → hijau tua | 0.0998–5.1405, domain tetap untuk 24 bagian |

Rentang ini untuk visualisasi, bukan klasifikasi ilmiah “aman”, “optimal”, atau “potensi tinggi”. Sampai unit terkonfirmasi, jangan tambahkan `%`, `°C`, atau `m` pada nilai observasi. Ukuran grid boleh disebut meter karena ukuran proyeksinya telah diuji. Untuk produksi, tampilkan legenda layer aktif dengan gradient, min/max, unit sah, waktu data, dan simbol NoData. Bila perbandingan antarperiode diperlukan, pertahankan domain warna yang sama atau nyatakan perubahan domain dengan jelas.

Jangan menerapkan heatmap/interpolasi default pada nilai ini: data sudah terikat pada sel tertentu. Untuk klorofil, pastikan satu entri per sel dipilih dahulu; 24 entri tidak boleh ditumpuk sebagai 24 pengamatan spasial independen pada footprint yang sama. Jika diperlukan raster kontinu, tentukan resampling secara eksplisit. Untuk kategori coral gunakan nearest-neighbor; data numerik boleh memakai metode lain hanya dengan justifikasi dan tanpa menyatakan piksel hasil resampling sebagai pengamatan baru.

## 14. Tap sel dan identitas data

Klik peta dikonversi dari WGS84 ke UTM, kemudian ke indeks:

```text
grid_x = floor((E - 637500) / 500) + 1
grid_y = floor((N - 8988000) / 500) + 1
```

Lookup `Map<GridId, Cell>` memberi semua angka sel tanpa ribuan listener polygon. Jika ID tidak ada, tampilkan “Tidak ada data”. Pembagian menggunakan konvensi interval kiri/bawah inklusif dan kanan/atas eksklusif; titik yang persis pada batas bersama dimasukkan ke sel timur/utara. Uji tap di sudut dan batas sel karena pembulatan koordinat dapat memengaruhi kasus tepat di garis.

Untuk detail habitat yang tepat, tambahkan point-in-polygon dengan spatial index di repository dan perhatikan holes, atau gunakan hit detection `PolygonLayer`. Tap contoh saat ini menampilkan data grid saja; ia belum memuat atribut habitat pada panel tap. Pisahkan ID fitur habitat dari ID sel grid. [API PolygonLayer](https://pub.dev/documentation/flutter_map/latest/flutter_map/PolygonLayer/PolygonLayer.html)

## 15. Performa dan strategi peningkatan

Ukuran sumber unik bertambah dari sekitar 3,98 MB menjadi **32,17 MB desimal** setelah klorofil-a, tetapi objek hasil parsing, ring, warna, dan polygon dapat memakai memori jauh lebih besar. Tiga layer numerik dasar berarti 94.062 polygon sel. Dengan satu entri klorofil aktif, total maksimum menjadi **125.416 polygon sel**, belum termasuk grid dan habitat. Jangan membuat 752.496 polygon dari seluruh berkas klorofil sekaligus.

Contoh paket sudah melakukan: pemuatan satu kali, parser di `compute`, join ke satu model per sel, cache vertex bersama, filter viewport dengan margin, debounce 150 ms, tanpa border pada isian numerik, grid saat zoom ≥12, deduplikasi sisi grid, dan widget layer disimpan di luar `build()`.

Filter viewport contoh masih melakukan scan linear atas 31.354 sel dan refresh membangun ulang layer aktif. Ini cukup sebagai implementasi awal untuk diukur, bukan jaminan frame rate. Slider juga memicu rebuild layer pada setiap perubahan; jika perangkat lambat, simpan nilai preview pada slider lalu terapkan render di `onChangeEnd`.

Urutan optimasi setelah profiling:

1. Pakai bucket/spatial index atau rentang indeks UTM untuk mengambil kandidat viewport tanpa scan semua sel. Cache bbox/ring per sel; gunakan vertex yang sama untuk sel tetangga agar tak ada celah akibat pembulatan.
2. Cache polygon/style per versi data dan layer. Invalidasi hanya layer yang berubah, bukan seluruh layer saat satu toggle diganti.
3. Pertahankan viewport buffer satu sel dan batalkan hasil pekerjaan lama saat ada pan berikutnya. Jangan menyimpan cache setiap kombinasi viewport tanpa batas.
4. Gunakan built-in polygon culling. Sel empat titik umumnya tidak memerlukan simplification; contoh mengaturnya 0. Habitat dapat disederhanakan pada salinan turunan dengan toleransi yang diuji dalam meter, tanpa menghilangkan holes kecil yang penting. [Optimasi polygon flutter_map](https://docs.fleaflet.dev/layers/polygon-layer)
5. Untuk overview, produksi raster/XYZ tile dari grid pada server atau tahap build dan pertahankan data numerik untuk lookup. Reproject raster sumber UTM ke Web Mercator sebelum membuat tile. Jangan memasang raster UTM sebagai gambar longitude/latitude dengan hanya dua sudut.
6. Untuk dataset besar/sering berubah, sediakan endpoint bbox, level of detail, atau tile per layer, dengan cache berdasarkan `dataset_version/layer/z/x/y`. Layer habitat dapat memakai vector tile bila kebutuhan styling/hit detection mendukung.

Target penerimaan yang disarankan, **belum diukur**: pan/zoom normal mendekati 60 fps pada perangkat target, pekerjaan UI per frame sekitar 16,7 ms pada layar 60 Hz, loading tidak membekukan gesture, serta pemakaian memori stabil setelah buka/tutup halaman dan toggle berulang. Gunakan Flutter DevTools pada profile build. Tentukan anggaran waktu muat dan memori bersama tim berdasarkan perangkat, bukan hanya jumlah baris.

## 16. Pembaruan data dan kontrak manifest

Pisahkan manifest dari nilai agar frontend tidak menebak satuan atau origin dari nama berkas. Contoh kontrak berikut adalah **usulan**, bukan metadata asli:

```json
{
  "schema_version": 1,
  "dataset_version": "snapshot-audit-2026-10-16",
  "bounds_lon_lat": [112.25, -9.15, 113.10, -8.35],
  "coordinate_crs": "OGC:CRS84",
  "grid": {
    "crs": "EPSG:32749",
    "origin_lower_left": [637500, 8988000],
    "size_m": 500,
    "indices_start_at": 1,
    "coordinate_role": "cell_center",
    "status": "inferred_from_coordinates"
  },
  "units": {"fish": null, "temperature": null, "depth": null, "chlorophyll": null},
  "chlorophyll": {"entry_count_per_cell": 24, "entry_axis": "export_order_only", "time_axis": null},
  "observed_at": null,
  "nodata": null,
  "coral_codebook_confirmed": false
}
```

Gunakan `null` sebagai belum diketahui, bukan pernyataan bahwa NoData tidak pernah ada. Isi waktu audit terpisah dari waktu observasi. Unduh pembaruan ke cache sementara, verifikasi hash/schema/CRS/grid, lalu ganti snapshot secara atomik; jangan campurkan ikan versi baru dengan suhu/kedalaman versi lama. Simpan versi terakhir yang valid bila pembaruan gagal dan beri informasi freshness yang jelas.

## 17. Checklist penerimaan frontend

- [ ] Bounds dan tanda negatif lintang benar; tombol reset menampilkan AOI pada ponsel dan layar lebar.
- [ ] Hanya satu berkas kedalaman dimuat; setiap dataset numerik mempunyai 31.354 key unik pada snapshot ini.
- [ ] Sel `(149,1)` menampilkan `16.35`, `29.136`, `5000.0` sesuai sumber.
- [ ] Ketiga layer numerik dasar, klorofil yang dipilih, dan grid sejajar pada sel yang sama, termasuk setelah pan/zoom/rotasi.
- [ ] Grid mempunyai sisi 500 m di EPSG:32749 dan memakai origin yang dinyatakan, bukan offset derajat perkiraan.
- [ ] Sel yang tidak tersedia tampil NoData; angka 5000 tidak disembunyikan sebagai NoData tanpa metadata.
- [ ] Coral kode 0 tidak seluruhnya diisi sebagai coral; asumsi kode 1 ditandai sampai terkonfirmasi.
- [ ] Aset coral hasil perbaikan dipakai; MultiPolygon dan holes tampil benar; mangrove holes tetap kosong.
- [ ] Toggle mempertahankan urutan relatif 1–7, dengan klorofil opsional setelah ikan, grid tanpa fill dan tidak menghalangi tap.
- [ ] Opacity/legenda konsisten; saat beberapa numerik aktif, dampak campuran warna dijelaskan pada UX.
- [ ] Data berada dalam AOI; perilaku kamera luar AOI sesuai pilihan center constraint/viewport constraint.
- [ ] Loading/error asset, perubahan schema, nilai invalid, dan snapshot tidak selaras menghasilkan pesan yang jelas.
- [ ] Sumber, unit, waktu, lisensi, arti kelas, dan metadata NoData dikonfirmasi sebelum label ilmiah difinalisasi.
- [ ] Klorofil diperlakukan sebagai 24 entri per sel; tidak ada penghapusan duplikat, pemilihan nilai terakhir, rerata otomatis, atau label bulan.
- [ ] Pemilih entri memuat satu bagian saja, menangani loading/error, dan tidak menampilkan hasil request lama dengan label baru.
- [ ] Build Android release dapat mengakses tile, web tidak gagal CORS, attribution tidak tertutup panel.
- [ ] `flutter analyze`, pemeriksaan visual, dan profiling dijalankan di proyek penerima. Hasil data audit tidak menggantikan uji aplikasi.

## 18. Bukti audit yang dapat dicocokkan

Hash SHA-256 sumber:

```text
coralreef(1).geojson
62c71b6c124e2d5913d0a244cbd2544a5f4d5fc8ee8ea4fdc12204db28fce57b

potensi_ikan.csv
1df4f1001c2f63bb0c1d8c8e921a9e924b37d68c4d9a226857b9b401a27cf56b

suhu_laut.csv
33aed0e16d69dea6cee0ed8fd6d559bdf850dfc67e2864895c91e8abc3d9b65a

kedalaman_laut.csv DAN kedalaman_laut (1).csv
3c387d6dda01cabf1a689e09e87ccfb30d6fda7242d22e1e850445fbf9181eba

mangrove_2023_jatim.geojson
e75f91181bd02d1b31fb448f10c0fbd1a9df1af2594cd612c6cd2ec7c9e8c15e

klorofil_a.csv
4e884e8a16b7b4193d81968607658e3b4f50df32ae43bbc17cd790e149fcb8a7
```

`validation_report.json` memuat hasil audit lengkap, termasuk alasan validitas per fitur. Hash di atas untuk **sumber asli**, bukan GeoJSON turunan yang telah dinormalisasi. Salinan CSV dalam paket mempertahankan hash sumbernya.

## 19. Tambahan klorofil-a: temuan, kontrak, dan integrasi

### Hasil pemeriksaan langsung

`klorofil_a.csv` memakai header yang sama persis:

```csv
grid_x,grid_y,latitude,longitude,value
149,1,-9.14772,112.9269473,0.2612
150,1,-9.1476958,112.9314956,0.2672
151,1,-9.1476715,112.9360439,0.2501
```

| Pemeriksaan | Hasil |
|---|---|
| Ukuran | 28.188.684 byte, sekitar 28,19 MB desimal |
| Baris data | **752.496 = 24 × 31.354** |
| Pasangan grid unik | **31.354**, sama dengan seluruh key CSV dasar |
| Entri pada setiap key | **tepat 24**, tanpa pengecualian |
| Urutan key | setiap bagian berurutan 31.354 baris sama persis dengan CSV ikan |
| Koordinat | seluruh baris cocok persis dengan sel referensi; delta maksimum 0° |
| Di luar AOI / angka invalid | 0 / 0 |
| Nilai | 0.0998–5.1405; tidak ada nol atau nilai negatif |
| Key dengan nilai berbeda antarentri | **31.354**, yaitu seluruh sel |
| Pengulangan baris numerik identik | 981; tetap dipertahankan |
| Kolom pembeda waktu/jenis/kedalaman | **tidak ada** |

Pemilik menyatakan ini adalah ekspor XY/latitude/longitude/value dan tidak memberikan keterangan periode. Karena itu 24 bagian **tidak ditafsirkan sebagai bulan, tahun, atau urutan kronologis**. Kemungkinan penyebab pengulangan juga tidak dapat dibuktikan dari CSV saja. Istilah “entri” di panduan hanya berarti baris sumber untuk satu sel.

Contoh sel `(149,1)` mempunyai nilai pertama `0.2612`, kedua `0.1742`, dan terakhir `0.1917`, dengan koordinat sama. Jadi berkas ini bukan 24 salinan identik dari satu peta. Di beberapa sel, angka tertentu kebetulan berulang; menghapus 981 baris identik akan mengubah jumlah entri per sel dan merusak keselarasan bagian.

### Kontrak yang aman untuk frontend

Key spasial saja `(grid_x, grid_y)` **belum unik** untuk berkas klorofil mentah. Gunakan key sementara `(entry_index, grid_x, grid_y)`, dengan `entry_index = 1..24` berdasarkan urutan kemunculan per sel. Nomor ini membantu menjaga data utuh, bukan metadata ilmiah baru.

Jangan langsung memasukkan seluruh CSV ke `Map<GridId, double>`: assignment akan menimpa 23 nilai dan menyisakan nilai terakhir tanpa penjelasan. Parser ketat sebelumnya sengaja akan menolak key duplikat. Jangan menghapus duplikat atau menghitung mean/median/max untuk menetapkan nilai tunggal tanpa keputusan dari pemilik data. Join mentah dengan dataset lain juga menghasilkan 24 baris untuk setiap sel, bukan 24 sel baru.

Untuk **peta klorofil tunggal yang siap dijadikan hasil analisis**, tim data masih perlu menetapkan dimensi pembeda entri atau aturan pemilihan/agregasi yang disetujui. Jika memang seharusnya satu nilai per sel, minta ekspor yang sudah unik beserta metadata sumber. Panduan ini tidak mengubah 24 nilai menjadi satu nilai final.

Unit klorofil juga belum tercantum. Gunakan “Klorofil-a (nilai)” sampai unit dikonfirmasi; jangan otomatis memberi label mg/m³ atau menetapkan ambang produktivitas dari rentang angka saja. Hubungan dengan potensi ikan tidak dihitung dari berkas ini tanpa model dan waktu yang sesuai.

### Aset dan pratinjau pada contoh Flutter

Untuk menghindari parsing 28 MB pada setiap pergantian tampilan, preprocessing telah membagi sumber menjadi 24 bagian, masing-masing satu entri untuk setiap sel:

```text
assets/geodata/klorofil_a/
  blok_01.csv
  ...
  blok_24.csv
  manifest.json
```

Split ini mempertahankan semua nilai, urutan baris, dan string field sumber; header ditulis ulang dengan newline LF. Tidak dilakukan agregasi, pembulatan nilai, pemilihan berdasarkan besar angka, atau pembuangan baris. CSV sumber 28 MB tidak disertakan ulang sebagai satu berkas utuh dalam ZIP, karena seluruh isinya sudah ada pada 24 bagian. Hash sumber dan batas baris setiap bagian tersimpan dalam manifest agar dapat ditelusuri.

Kecocokan blok lengkap telah diperiksa pada **seluruh 24 × 31.354 baris**, bukan disimpulkan hanya dari 24 kemunculan titik pertama. Ini memungkinkan pemilih pratinjau **“Entri per sel (urutan ekspor) 1/24 … 24/24”**. Pergantian memilih entri ke-n untuk setiap sel; label tidak menyebut tanggal. Layer klorofil **nonaktif secara default** agar pratinjau tidak terlihat seperti satu peta final yang telah dipilih pemilik data.

`ChlorophyllRepository` memuat satu bagian saat diperlukan dan menyimpan maksimal dua bagian dalam cache. ID/koordinat dicek terhadap model dasar sebelum render. Hasil loading lama diabaikan bila pengguna telah memilih entri baru. Geometry grid dan origin dipakai bersama layer lain; tidak dibuat grid baru untuk tiap bagian.

Letak tambahan sementara adalah setelah potensi ikan dan sebelum mangrove. Urutan relatif tujuh layer lama tetap dipertahankan, dan grid tetap paling atas. Style pratinjau memakai domain tetap `0.0998–5.1405` agar perbandingan antarentri tidak berubah karena rescaling otomatis. Nomor entri dan catatan bahwa satuan/dimensi belum diketahui tetap ada di UI.

Pastikan `pubspec.yaml` juga mendaftarkan **subdirektori** `assets/geodata/klorofil_a/`; deklarasi direktori induk tidak otomatis mencakup seluruh subdirektori. Berkas `manifest.json` disertakan untuk audit dan kontrak data; contoh Dart mengunci jumlah 24 sesuai snapshot ini.

### Mengulang preprocessing

Script `tools/audit_prepare.py` revisi 2 memeriksa keenam berkas awal, kemudian memanggil preprocessing klorofil dari folder sumber yang sama. Jalankan pada folder terpisah berisi tujuh berkas sumber. Script `prepare_chlorophyll.py` juga bisa dijalankan sendiri:

```sh
python tools/prepare_chlorophyll.py --input /sumber/klorofil_a.csv --reference /sumber/potensi_ikan.csv --output /hasil/klorofil_a
```

Jika jumlah bagian, isi key, urutan, atau koordinat berubah pada ekspor berikutnya, script menolak snapshot tersebut. Jangan memaksa split berukuran tetap sebelum mengaudit ulang ekspor yang berubah.

## 20. Contoh kode Dart lengkap, revisi 2

Lima modul berikut sama dengan yang disertakan dalam paket pendamping. Contoh menyediakan toggle, opacity, legenda teks, reset bounds, loading/error, panel nilai grid, dan pratinjau entri klorofil. Kode Flutter tetap belum dikompilasi atau diuji perangkat di lingkungan pembuat paket.

### `geodata.dart`

```dart
import 'dart:convert';
import 'package:csv/csv.dart';

typedef GridId = (int, int);

class Sample {
  final GridId id;
  final double lat, lon, value;
  const Sample(this.id, this.lat, this.lon, this.value);
}

class Cell {
  final GridId id;
  final double lat, lon, fish, temperature, depth;
  const Cell(this.id, this.lat, this.lon, this.fish,
      this.temperature, this.depth);
}

class AreaPart {
  final String id;
  // Setiap ring berupa pasangan [longitude, latitude]. Ring 0 = exterior.
  final List<List<List<double>>> rings;
  final Map<String, dynamic> properties;
  const AreaPart(this.id, this.rings, this.properties);
}

class MarineData {
  final Map<GridId, Cell> cells;
  final List<AreaPart> coral, mangrove;
  const MarineData(this.cells, this.coral, this.mangrove);
}

Map<GridId, Sample> parseSamples(String text) {
  final table = Csv(fieldDelimiter: ',').decode(text.replaceFirst('\uFEFF', ''));
  if (table.isEmpty) throw const FormatException('CSV kosong');
  final headers = table.first.map((v) => v.toString().trim()).toList();
  const expected = ['grid_x', 'grid_y', 'latitude', 'longitude', 'value'];
  if (headers.length != 5 || headers.toSet().length != 5 ||
      !expected.every(headers.contains)) {
    throw FormatException('Header CSV tidak sesuai: $headers');
  }
  final out = <GridId, Sample>{};
  for (var i = 1; i < table.length; i++) {
    final row = table[i];
    if (row.every((v) => v.toString().trim().isEmpty)) continue;
    if (row.length != headers.length) {
      throw FormatException('Jumlah kolom salah pada baris ${i + 1}');
    }
    double number(String key) {
      final v = double.tryParse(row[headers.indexOf(key)].toString().trim());
      if (v == null || !v.isFinite) {
        throw FormatException('$key tidak valid pada baris ${i + 1}');
      }
      return v;
    }
    final x = number('grid_x'), y = number('grid_y');
    if (x != x.roundToDouble() || y != y.roundToDouble() ||
        x < 1 || x > 187 || y < 1 || y > 177) {
      throw FormatException('Indeks grid tidak valid pada baris ${i + 1}');
    }
    final lat = number('latitude'), lon = number('longitude');
    if (lat < -9.15 || lat > -8.35 || lon < 112.25 || lon > 113.10) {
      throw FormatException('Titik di luar AOI pada baris ${i + 1}');
    }
    final id = (x.toInt(), y.toInt());
    if (out.containsKey(id)) throw FormatException('Grid duplikat: $id');
    out[id] = Sample(id, lat, lon, number('value'));
  }
  return out;
}

List<AreaPart> parseAreas(String text) {
  final root = jsonDecode(text) as Map<String, dynamic>;
  if (root['type'] != 'FeatureCollection') {
    throw const FormatException('Harus FeatureCollection');
  }
  final result = <AreaPart>[];
  final features = root['features'] as List<dynamic>;
  for (var i = 0; i < features.length; i++) {
    final f = features[i] as Map<String, dynamic>;
    final g = f['geometry'] as Map<String, dynamic>;
    final props = Map<String, dynamic>.from(f['properties'] as Map? ?? {});
    final coords = g['coordinates'] as List<dynamic>;
    final List<dynamic> polygons;
    if (g['type'] == 'Polygon') {
      polygons = [coords];
    } else if (g['type'] == 'MultiPolygon') {
      polygons = coords;
    } else {
      throw FormatException('Geometri tidak didukung: ${g['type']}');
    }
    for (var p = 0; p < polygons.length; p++) {
      final rings = <List<List<double>>>[];
      for (final rawRing in polygons[p] as List<dynamic>) {
        final ring = <List<double>>[];
        for (final rawPoint in rawRing as List<dynamic>) {
          final point = rawPoint as List<dynamic>;
          if (point.length < 2) throw const FormatException('Koordinat kurang');
          final lon = (point[0] as num).toDouble();
          final lat = (point[1] as num).toDouble();
          if (!lon.isFinite || !lat.isFinite ||
              lon < 112.25 || lon > 113.10 || lat < -9.15 || lat > -8.35) {
            throw const FormatException('Area belum dinormalisasi ke AOI');
          }
          ring.add([lon, lat]);
        }
        if (ring.length < 4 || ring.first[0] != ring.last[0] ||
            ring.first[1] != ring.last[1]) {
          throw const FormatException('Ring tidak tertutup');
        }
        rings.add(ring);
      }
      if (rings.isEmpty) throw const FormatException('Polygon tanpa ring');
      result.add(AreaPart('${f['id'] ?? i}:$p', rings, props));
    }
  }
  return result;
}

// Fungsi top-level untuk compute(); hanya data biasa, tanpa widget/Color.
MarineData decodeMarineData(Map<String, String> texts) {
  final fish = parseSamples(texts['fish']!);
  final temperature = parseSamples(texts['temperature']!);
  final depth = parseSamples(texts['depth']!);
  if (fish.length != 31354 || temperature.length != fish.length ||
      depth.length != fish.length) {
    throw const FormatException('Jumlah sel berbeda dari snapshot audit');
  }
  final cells = <GridId, Cell>{};
  for (final entry in fish.entries) {
    final f = entry.value, t = temperature[entry.key], d = depth[entry.key];
    if (t == null || d == null || (t.lat - f.lat).abs() > 1e-7 ||
        (t.lon - f.lon).abs() > 1e-7 || (d.lat - f.lat).abs() > 1e-7 ||
        (d.lon - f.lon).abs() > 1e-7) {
      throw FormatException('Join tidak selaras pada ${entry.key}');
    }
    cells[entry.key] = Cell(entry.key, f.lat, f.lon,
        f.value, t.value, d.value);
  }
  return MarineData(cells, parseAreas(texts['coral']!),
      parseAreas(texts['mangrove']!));
}
```

### `grid_projection.dart`

```dart
import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj;
import 'geodata.dart';

class GridProjection {
  static const originE = 637500.0, originN = 8988000.0, step = 500.0;
  final proj.Projection wgs = proj.Projection.get('EPSG:4326')!;
  final proj.Projection utm = proj.Projection.parse(
      '+proj=utm +zone=49 +south +datum=WGS84 +units=m +no_defs');
  final Map<(int, int), LatLng> _vertices = {};

  LatLng vertex(int ix, int iy) => _vertices.putIfAbsent((ix, iy), () {
    final p = utm.transform(wgs, proj.Point(
        x: originE + ix * step, y: originN + iy * step));
    return LatLng(p.y, p.x);
  });

  List<LatLng> ring(GridId id) {
    final x = id.$1 - 1, y = id.$2 - 1;
    return [vertex(x, y), vertex(x + 1, y),
      vertex(x + 1, y + 1), vertex(x, y + 1)];
  }

  GridId idAt(LatLng position) {
    final p = wgs.transform(utm,
        proj.Point(x: position.longitude, y: position.latitude));
    return (((p.x - originE) / step).floor() + 1,
        ((p.y - originN) / step).floor() + 1);
  }

  void validateCenter(Cell cell) {
    final p = wgs.transform(utm, proj.Point(x: cell.lon, y: cell.lat));
    final e = originE + (cell.id.$1 - 0.5) * step;
    final n = originN + (cell.id.$2 - 0.5) * step;
    if ((p.x - e).abs() > 0.05 || (p.y - n).abs() > 0.05) {
      throw FormatException('Origin grid tidak cocok pada ${cell.id}');
    }
  }
}
```

### `map_layers.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'geodata.dart';
import 'grid_projection.dart';

enum LayerId { coral, fish, chlorophyll, mangrove, temperature, depth, grid }

const layerLabels = {
  LayerId.coral: 'Coral (kode 1, sementara)',
  LayerId.fish: 'Potensi ikan (nilai)',
  LayerId.chlorophyll: 'Klorofil-a (pratinjau entri)',
  LayerId.mangrove: 'Mangrove 2023',
  LayerId.temperature: 'Suhu laut (nilai)',
  LayerId.depth: 'Kedalaman (nilai)',
  LayerId.grid: 'Grid 500 m (zoom ≥12)',
};

// Batas style mengikuti rentang snapshot; bukan ambang ilmiah.
Color thematicColor(LayerId layer, Cell c, double opacity,
    {double? chlorophyll}) {
  final (v, min, max, low, high) = switch (layer) {
    LayerId.fish => (c.fish, 1.0, 100.0,
        const Color(0xFFFFFFCC), const Color(0xFF006837)),
    LayerId.temperature => (c.temperature, 27.964, 30.391,
        const Color(0xFF2166AC), const Color(0xFFB2182B)),
    LayerId.depth => (c.depth, 18.0, 5000.0,
        const Color(0xFFDEEBF7), const Color(0xFF08306B)),
    LayerId.chlorophyll => (chlorophyll!, 0.0998, 5.1405,
        const Color(0xFFFFFFCC), const Color(0xFF004529)),
    _ => throw ArgumentError('Bukan layer tematik'),
  };
  final t = ((v - min) / (max - min)).clamp(0.0, 1.0).toDouble();
  return Color.lerp(low, high, t)!.withValues(alpha: opacity);
}

List<Polygon<String>> areaPolygons(List<AreaPart> parts, Color color,
    {bool onlyCoralCodeOne = false}) {
  return [
    for (final part in parts)
      if (!onlyCoralCodeOne ||
          (part.properties['value'] as num?)?.toDouble() == 1.0)
        Polygon<String>(
          points: [for (final p in part.rings.first) LatLng(p[1], p[0])],
          holePointsList: [for (final ring in part.rings.skip(1))
            [for (final p in ring) LatLng(p[1], p[0])]],
          color: color, borderColor: color, borderStrokeWidth: 0.7,
        ),
  ];
}

List<Polygon<String>> cellPolygons(Iterable<Cell> cells,
    GridProjection projection, LayerId layer, double opacity,
    {Map<GridId, double> chlorophyll = const {}}) => [
  for (final c in cells)
    if (layer != LayerId.chlorophyll || chlorophyll.containsKey(c.id))
      Polygon<String>(points: projection.ring(c.id),
        color: thematicColor(layer, c, opacity,
            chlorophyll: chlorophyll[c.id]), borderStrokeWidth: 0),
];

// Berbagi vertex dan deduplikasi sisi; garis tetangga digambar satu kali.
List<Polyline<String>> gridLines(Iterable<Cell> cells, GridProjection p) {
  final edges = <String, Polyline<String>>{};
  for (final c in cells) {
    final x = c.id.$1 - 1, y = c.id.$2 - 1;
    final specs = [
      ('h:$x:$y', (x, y), (x + 1, y)),
      ('h:$x:${y + 1}', (x, y + 1), (x + 1, y + 1)),
      ('v:$x:$y', (x, y), (x, y + 1)),
      ('v:${x + 1}:$y', (x + 1, y), (x + 1, y + 1)),
    ];
    for (final e in specs) {
      edges.putIfAbsent(e.$1, () => Polyline<String>(
          points: [p.vertex(e.$2.$1, e.$2.$2), p.vertex(e.$3.$1, e.$3.$2)],
          color: const Color(0x77555555), strokeWidth: 0.5));
    }
  }
  return edges.values.toList();
}
```

### `chlorophyll_repository.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'geodata.dart';

// Memuat satu entri per sel, mempertahankan 24 entri dalam asset terpisah.
// Nomor adalah urutan ekspor; tidak menyatakan waktu atau kualitas data.
class ChlorophyllRepository {
  final Map<int, Map<GridId, double>> _cache = {};

  Future<Map<GridId, double>> loadEntry(int entry, MarineData reference) async {
    if (entry < 1 || entry > 24) throw RangeError.range(entry, 1, 24);
    if (_cache.containsKey(entry)) {
      final values = _cache.remove(entry)!;
      _cache[entry] = values;
      return values;
    }
    final name = entry.toString().padLeft(2, '0');
    final text = await rootBundle.loadString(
        'assets/geodata/klorofil_a/blok_$name.csv');
    final samples = await compute(parseSamples, text);
    if (samples.length != reference.cells.length) {
      throw const FormatException('Jumlah sel klorofil berbeda dari referensi');
    }
    final values = <GridId, double>{};
    for (final row in samples.entries) {
      final cell = reference.cells[row.key];
      if (cell == null || (cell.lat - row.value.lat).abs() > 1e-7 ||
          (cell.lon - row.value.lon).abs() > 1e-7) {
        throw FormatException('Klorofil tidak selaras pada ${row.key}');
      }
      values[row.key] = row.value.value;
    }
    _cache[entry] = values;
    while (_cache.length > 2) {
      _cache.remove(_cache.keys.first);
    }
    return values;
  }
}
```

### `main.dart`

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'geodata.dart';
import 'grid_projection.dart';
import 'map_layers.dart';
import 'chlorophyll_repository.dart';

void main() => runApp(const MaterialApp(home: MarineMapPage()));

final aoi = LatLngBounds(const LatLng(-9.15, 112.25),
    const LatLng(-8.35, 113.10));

class MarineMapPage extends StatefulWidget {
  const MarineMapPage({super.key});
  @override
  State<MarineMapPage> createState() => _MarineMapPageState();
}

class _MarineMapPageState extends State<MarineMapPage> {
  final _controller = MapController();
  final _projection = GridProjection();
  final _chlorophyllRepository = ChlorophyllRepository();
  Map<GridId, double> _chlorophyllValues = {};
  int _chlorophyllEntry = 1;
  int _chlorophyllRequest = 0;
  bool _chlorophyllLoading = false;
  Object? _chlorophyllError;
  final _enabled = {LayerId.coral, LayerId.fish, LayerId.mangrove, LayerId.grid};
  final _opacity = {for (final id in LayerId.values) id: 0.55};
  final _layers = <LayerId, Widget>{};
  MarineData? _data;
  Object? _error;
  Timer? _timer;
  LatLngBounds? _view;
  double _zoom = 9;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      const paths = {
        'fish': 'potensi_ikan.csv', 'temperature': 'suhu_laut.csv',
        'depth': 'kedalaman_laut.csv', 'coral': 'coral.geojson',
        'mangrove': 'mangrove.geojson',
      };
      final entries = await Future.wait(paths.entries.map((e) async =>
          MapEntry(e.key, await rootBundle.loadString('assets/geodata/${e.value}'))));
      final data = await compute(decodeMarineData, Map<String, String>.fromEntries(entries));
      // QA penuh pusat grid dilakukan offline; cek kontrol saat startup.
      _projection.validateCenter(data.cells[(149, 1)]!);
      if (!mounted) return;
      _data = data;
      _refreshLayers();
      if (_enabled.contains(LayerId.chlorophyll)) {
        _loadChlorophyll(_chlorophyllEntry);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadChlorophyll(int entry) async {
    final request = ++_chlorophyllRequest;
    _chlorophyllEntry = entry;
    _chlorophyllValues = {};
    _chlorophyllError = null;
    _chlorophyllLoading = _data != null;
    _refreshLayers();
    if (_data == null) return;
    try {
      final values = await _chlorophyllRepository.loadEntry(entry, _data!);
      if (!mounted || request != _chlorophyllRequest) return;
      _chlorophyllValues = values;
    } catch (e) {
      if (!mounted || request != _chlorophyllRequest) return;
      _chlorophyllError = e;
    }
    if (!mounted || request != _chlorophyllRequest) return;
    _chlorophyllLoading = false;
    _refreshLayers();
  }

  void _refreshLayers() {
    final data = _data;
    if (!mounted) return;
    if (data == null) {
      setState(() {});
      return;
    }
    final view = _view ?? aoi;
    // Filter bbox, bukan hanya titik pusat, agar sel di tepi layar tidak hilang.
    // Margin 0.006° > setengah diagonal sel 500 m pada AOI ini.
    final visible = data.cells.values.where((c) =>
        c.lat >= view.south - 0.006 && c.lat <= view.north + 0.006 &&
        c.lon >= view.west - 0.006 && c.lon <= view.east + 0.006).toList();
    _layers.clear();
    for (final id in _enabled) {
      if (id == LayerId.coral || id == LayerId.mangrove) {
        final coral = id == LayerId.coral;
        final color = (coral ? const Color(0xFFF28E2B) : const Color(0xFF238443))
            .withValues(alpha: _opacity[id]!);
        _layers[id] = PolygonLayer<String>(
          polygons: areaPolygons(coral ? data.coral : data.mangrove,
            color, onlyCoralCodeOne: coral),
          polygonCulling: true, drawInSingleWorld: true,
        );
      } else if (id == LayerId.grid) {
        if (_zoom >= 12) {
          _layers[id] = IgnorePointer(child: PolylineLayer<String>(
              polylines: gridLines(visible, _projection),
              simplificationTolerance: 0, drawInSingleWorld: true));
        }
      } else {
        _layers[id] = PolygonLayer<String>(
            polygons: cellPolygons(visible, _projection, id, _opacity[id]!,
                chlorophyll: _chlorophyllValues),
            polygonCulling: true, simplificationTolerance: 0,
            drawInSingleWorld: true);
      }
    }
    setState(() {});
  }

  void _showCell(LatLng point) {
    if (!aoi.contains(point)) return;
    final id = _projection.idAt(point);
    final cell = _data?.cells[id];
    showModalBottomSheet<void>(context: context, builder: (context) =>
      SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Text(
        cell == null ? 'Tidak ada data pada sel $id' :
        'Sel ${id.$1}:${id.$2}\n'
        'Pusat: ${cell.lat}, ${cell.lon}\n'
        'Potensi ikan: ${cell.fish}\nSuhu: ${cell.temperature}\n'
        'Kedalaman: ${cell.depth}\n'
        'Klorofil-a, entri $_chlorophyllEntry: '
        '${_chlorophyllValues[id] ?? "belum dimuat"}\n'
        'Nomor entri hanya urutan ekspor, tanpa informasi waktu.\n'
        'Satuan dan waktu observasi CSV belum dikonfirmasi.',
      ))));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Peta laut — contoh handoff'), actions: [
      IconButton(icon: const Icon(Icons.fit_screen), tooltip: 'Kembali ke area',
        onPressed: () {
          if (_ready) _controller.fitCamera(CameraFit.bounds(
              bounds: aoi, padding: const EdgeInsets.all(24)));
        }),
    ]),
    drawer: Drawer(child: SafeArea(child: ListView(children: [
      const ListTile(title: Text('Layer dari bawah ke atas')),
      for (final id in LayerId.values) ...[
        SwitchListTile(title: Text(layerLabels[id]!), value: _enabled.contains(id),
          onChanged: (value) {
            if (value) { _enabled.add(id); } else { _enabled.remove(id); }
            _refreshLayers();
            if (id == LayerId.chlorophyll && value) {
              _loadChlorophyll(_chlorophyllEntry);
            }
          }),
        if (id == LayerId.chlorophyll && _enabled.contains(id)) ...[
          ListTile(title: const Text('Entri per sel (urutan ekspor)'),
            subtitle: const Text('Pratinjau; bukan periode atau nilai tunggal final.'),
            trailing: DropdownButton<int>(value: _chlorophyllEntry,
              items: [for (var i = 1; i <= 24; i++)
                DropdownMenuItem(value: i, child: Text('$i / 24'))],
              onChanged: (v) { if (v != null) _loadChlorophyll(v); })),
          if (_chlorophyllLoading) const LinearProgressIndicator(),
          if (_chlorophyllError != null)
            ListTile(title: Text('Gagal memuat klorofil: $_chlorophyllError'),
              trailing: IconButton(icon: const Icon(Icons.refresh),
                onPressed: () => _loadChlorophyll(_chlorophyllEntry))),
        ],
        if (id != LayerId.grid && _enabled.contains(id))
          Slider(value: _opacity[id]!, min: 0, max: 1, divisions: 20,
            label: '${(_opacity[id]! * 100).round()}%',
            onChanged: (v) { _opacity[id] = v; _refreshLayers(); }),
      ],
      const ListTile(title: Text('Legenda nilai snapshot'), subtitle: Text(
        'Ikan: kuning 1 → hijau 100\n'
        'Suhu: biru 27.964 → merah 30.391\n'
        'Kedalaman: biru muda 18 → biru tua 5000\n'
        'Klorofil-a: kuning muda 0.0998 → hijau tua 5.1405\n'
        'Rentang visual; satuan belum dikonfirmasi.\n'
        'Kode coral 1 ditampilkan sebagai asumsi sementara.')),
    ]))),
    body: Stack(children: [
      FlutterMap(mapController: _controller, options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: aoi,
            padding: const EdgeInsets.all(24)),
        cameraConstraint: CameraConstraint.containCenter(bounds: aoi),
        minZoom: 7, maxZoom: 18,
        onMapReady: () { _ready = true; },
        onTap: (_, point) => _showCell(point),
        onPositionChanged: (camera, hasGesture) {
          _view = camera.visibleBounds; _zoom = camera.zoom;
          _timer?.cancel();
          _timer = Timer(const Duration(milliseconds: 150), _refreshLayers);
        },
      ), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'id.example.marine_map_handoff',
          maxNativeZoom: 19),
        // Klorofil adalah layer tambahan setelah ikan; urutan lama tetap relatif.
        for (final id in LayerId.values)
          if (_layers.containsKey(id)) _layers[id]!,
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ]),
      if (_data == null && _error == null)
        const Center(child: CircularProgressIndicator()),
      if (_error != null)
        Center(child: Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Text('Gagal memuat data: $_error')))),
    ]),
  );
}
```


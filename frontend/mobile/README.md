# Reefish Mobile — peta laut dan pencatatan perjalanan

Aplikasi Flutter untuk membantu nelayan melihat petak laut, memeriksa status pembatasan, mencatat perjalanan, dan membaca cuaca serta rekomendasi. Fokus prototipe ini adalah memberi konteks keputusan dan pencatatan; peta, skor, dan rute tidak menggantikan penilaian keselamatan di laut.

## Demo lokal

Dari folder `frontend/mobile`, gunakan PowerShell dengan Flutter SDK terpasang:

```powershell
.\scripts\preview.ps1 -Port 4195
```

Buka `http://127.0.0.1:4195`. Preview menggunakan kode aplikasi Flutter di browser. Tambahkan konfigurasi lokal `config/supabase.local.json` untuk menghubungkan Supabase dan URL Go API. Berkas tersebut diabaikan Git; pakai URL dan publishable key saja, jangan pernah service-role key. Tanpa konfigurasi, preview tetap dapat dibuka tetapi layanan yang memerlukan backend akan menampilkan status belum terhubung.

Layar dapat dibuka langsung dengan `/?screen=welcome`, `/?screen=login`, `/?screen=signup`, `/?screen=departure`, `/?screen=journey`, atau `/?screen=dashboard`. Parameter URL hanya memilih layar; ia tidak membuat sesi atau data demo. Penguncian demo peta harus diminta eksplisit lewat `&demo-grid-locks=1` dan ditandai sebagai data demo.

Untuk membuat konfigurasi lokal dari contoh, isi salinan ini dengan endpoint dan kunci publik:

```powershell
Copy-Item config/supabase.example.json config/supabase.local.json
```

Setelah mengubah konfigurasi, hentikan lalu mulai ulang preview agar nilai build terbaru dimuat. Untuk menjalankan di device/emulator gunakan `scripts/run.ps1`; preview web tidak membuktikan izin lokasi, penyimpanan secure native, performa perangkat, atau perilaku status bar Android.

## Mengulang pemeriksaan Flutter

Dari folder `frontend/mobile`, jalankan pemeriksaan proyek yang tersedia:

```powershell
.\scripts\check.ps1
```

Script ini menjalankan resolusi dependency, analisis, seluruh tes, dan build web preview (`tool/preview.dart`). Jika Flutter SDK berada di lokasi lain, teruskan `-FlutterPath 'C:\lokasi\flutter\bin\flutter.bat'`. Hasil lama dan batasnya tetap dirujuk pada laporan terkait; menjalankan ulang script menghasilkan hasil untuk checkout dan konfigurasi lokal saat ini.

## Alur demonstrasi

1. Buka peta keberangkatan, pilih titik lewat peta/GPS, lalu periksa ringkasan petak. Buka **Detail data** untuk sumber, periode, nilai yang tersedia, dan status kebijakan.
2. Tunjukkan perbedaan antara petak terkunci dan status yang belum terverifikasi. Titik penangkapan tidak dapat disimpan ketika kebijakan belum diketahui atau petak terkunci. Login diperlukan untuk membaca snapshot kebijakan akun.
3. Masuk, lengkapi data kapal bila diminta, lalu catat perjalanan pertama. Form perjalanan mengirim waktu, BBM, tangkapan, dan lokasi lewat repository Supabase.
4. Di Dashboard, tunjukkan riwayat, cuaca dan rekomendasi. Cuaca datang dari Go API; rekomendasi saat ini diberi label heuristik, bukan keluaran model terlatih.
5. Untuk melihat antarmuka sesi berlayar, gunakan fixture QA di `qa/remaining/`. Sesi dan titik GPS di sana sintetis; jangan menyebutnya sebagai perjalanan tersimpan di server.

Panduan setup yang dapat diikuti juri dimulai dari preview web. APK rilis universal Android versi 1.0.1+3 dibangun dan pemeriksaan tanda tangan/manifest dicatat pada [laporan integrasi demo](../../docs/frontend/hackathon-integration.md) dan [panduan rilis](RELEASE.md). Distribusi APK dan kunci penandatanganan dikelola terpisah; jangan menambahkan berkas kunci ke repo.

## Rancangan teknis

Kode di `lib/src/` diorganisasikan per fitur, dengan lapisan `domain`, `data`, dan `presentation` bila relevan. Kontrak repository memisahkan aturan alur dari penyedia data. Cubit menangani form auth, peta, dan Journey; koordinasi sesi pelayaran berada pada `SailingBloc` yang menggunakan Cubit dan menyimpan transisi berurutan sebelum state dipancarkan.

- Auth memakai Supabase Auth, OTP SMS, pemulihan token, dan penyimpanan session native melalui `flutter_secure_storage`. Flutter web memakai penyimpanan bawaan Supabase pada origin browser.
- Journey memakai `SupabaseJourneyRepository` untuk profil, kapal, perjalanan, riwayat, dan detail; draft pending lokal mempertahankan UUID yang sama saat retry.
- Peta menggabungkan identitas sel canonical 500 m dengan repository Supabase untuk layer/habitat dan kebijakan, serta aset paket lokal sebagai snapshot yang dapat dibaca tanpa jaringan. Nilai hilang tetap NoData.
- Cuaca dan rekomendasi memakai Go API dengan JWT Supabase; pembagian endpoint dan kontrak ada di root `contracts/`.
- `SailingBloc` menyimpan sesi dan jejak foreground per akun pada penyimpanan lokal. Perjalanan yang selesai dapat dikirim sebagai draft ke backend ketika alur Journey berjalan. Ini belum menjadi sinkronisasi offline penuh berbasis outbox, dan tile peta tetap online.

Grid analitik tetap 500 × 500 m pada EPSG:32749. Grid bukan mask laut atau grafik navigasi. Basemap OSM digunakan online dengan atribusi; routing yang ada berstatus simulasi dan tidak boleh dipakai sebagai panduan operasional. Backend demo mengimpor prediksi untuk periode sumber 2025-12 saja. Snapshot lokal juga memuat 24 entri klorofil per sel; aplikasi menampilkan urutan entri tanpa menganggapnya tanggal, karena metadata sumber belum menetapkan pemetaan waktu dan satuan. Audit menemukan kecocokan numerik terhadap keluaran periode 2024-01–2025-12, tetapi itu belum mengesahkan provenance atau metadata. Satuan CSV dan kamus kelas coral juga belum lengkap; nilai-nilai tersebut bukan pengamatan terkini.

## Bukti dan batas verifikasi

- [Laporan integrasi demo](../../docs/frontend/hackathon-integration.md) mencatat pemeriksaan endpoint Supabase/Go, build APK rilis 1.0.1+3, serta batas demo yang diketahui. Bukti HTTP langsung tidak berarti semua alur telah diuji dari UI pada akun nyata.
- [QA sesi](qa/session/README.md) memeriksa login, reload, refresh token, gangguan jaringan dan logout dengan seluruh request Supabase diintersep; ini tidak memvalidasi secure storage native.
- [QA cuaca](qa/weather/README.md) memeriksa nilai normal/null/error pada fixture browser. Probe provider/API yang terpisah bukan uji end-to-end UI terautentikasi.
- [QA kebijakan petak](qa/grid-policy/README.md) memverifikasi status belum diketahui tetap memblokir pilihan; percobaan browser yang tercatat tidak menghasilkan lima ID sel yang berbeda dan memiliki overflow semantik pada 360 px.
- [QA popup peta](qa/map-popup/README.md), [benchmark pemilihan sel](qa/selection-performance/README.md), dan [QA layar sesi/visual](qa/remaining/README.md) mencatat pengukuran serta keterbatasannya.

Laporan uji per fitur adalah bukti dari waktu dan scope yang tercatat di file masing-masing, bukan angka gabungan untuk kondisi saat ini. Pemeriksaan otomatis memakai fixture tidak membuktikan data nelayan, keputusan konservasi, pengiriman SMS, atau perjalanan produksi. Uji native pada perangkat fisik dan evaluasi dampak lapangan masih menjadi pekerjaan berikutnya.

## Referensi implementasi peta

- [Audit dan ringkasan data laut](design/marine/README.md)
- [Contoh peta laut](examples/peta_laut/README.md)
- [Figma dan manifest aset](design/)
- [Panduan rilis APK](RELEASE.md)

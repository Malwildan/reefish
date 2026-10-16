# Reefish mobile — auth dan peta

Folder aplikasi: `D:\Reefish\frontend\mobile`. Jalankan perintah PowerShell dari folder ini.

Flutter source untuk empat frame pada Figma **High-Fidelity → mobile screen**:

- Splash `66:1141`
- Welcome `62:994`
- Create Account `78:29`
- Login `203:1790`

Source desain: [Figma](https://www.figma.com/design/rYWg8rKhaDB09bVKXXBMcK/JOINTS-BISMILLAH-YAALLAH-JUARA-1?node-id=203-1789).

## Menjalankan tanpa Android Studio atau emulator

Preview web menjalankan kode Flutter aplikasi ini di browser. Flutter SDK tetap diperlukan untuk mengompilasi; tidak diperlukan Android SDK untuk preview web. SDK dapat dipilih melalui PATH atau opsi `-FlutterPath` tanpa mengubah PATH Windows.

Dari folder proyek ini di PowerShell:

```powershell
.\scripts\preview.ps1
```

Lalu buka `http://127.0.0.1:4186` di Edge. Untuk SDK di lokasi lain:

```powershell
.\scripts\preview.ps1 -FlutterPath 'C:/lokasi/flutter/bin/flutter.bat'
```

Entry preview berada di `tool/preview.dart`: kanvas dibatasi sampai 430 × 932 dan menyisakan ruang safe area desain tanpa menggambar status bar palsu. Kamu bisa membuka `/?screen=welcome`, `/?screen=signup`, `/?screen=login`, atau `/?screen=splash`. Entry produksi `lib/main.dart` memakai safe area asli perangkat dan dimulai dari Splash.

Script mencari `flutter` di PATH terlebih dahulu, lalu instalasi laptop di `$env:USERPROFILE/develop/flutter/bin/flutter.bat`, dan terakhir SDK portable di `$env:USERPROFILE/.codex/toolchains/flutter/bin/flutter.bat`. Opsi `-FlutterPath` tetap bisa dipakai untuk lokasi lain. Menggunakan Edge sebagai device secara langsung juga didukung:

```powershell
.\scripts\run.ps1 -Device edge
```

Untuk pemeriksaan:

```powershell
.\scripts\check.ps1
```

Script menjalankan dependency resolution, analisis, tes, dan build web. Preview web memeriksa UI/interaksi Flutter; build dan perilaku keyboard/status bar native Android tetap perlu diverifikasi pada perangkat Android nanti.

## Batas fungsi autentikasi

Auth memakai Supabase Auth melalui `AuthRepository` dan `AuthCubit`. Konfigurasi hanya memakai URL proyek dan publishable key pada build; jangan masukkan secret/service-role key. Salin `config/supabase.example.json` menjadi `config/supabase.local.json` lalu isi nilainya. File lokal itu di-ignore Git. Tanpa konfigurasi, aplikasi tetap terbuka dan menampilkan pesan layanan belum terhubung.

`.\scripts\preview.ps1` memakai `config/supabase.local.json` bila tersedia untuk menjalankan preview dan mengaktifkan bootstrap yang sama dengan aplikasi utama. Jalankan aplikasi pada perangkat atau emulator dengan `.\scripts\run.ps1`; opsi `-Device` dan `-FlutterPath` tersedia. Status sesi dipulihkan oleh SDK, dipantau di atas route navigator, dan dibersihkan saat logout. Daftar tanpa sesi hanya membuka form verifikasi; sesi tidak dianggap berhasil sampai Supabase mengembalikan session. Layar setelah masuk mengonfirmasi sesi, menyediakan logout, dan memberi akses ke layar titik keberangkatan. Dashboard lengkap belum dibuat.

Jika preview sudah berjalan sebelum `config/supabase.local.json` dibuat atau diubah, hentikan proses preview dan mulai ulang dengan `scripts/preview.ps1`; dart-define dibaca saat proses Flutter dimulai. `qa/auth-connection/check-preview.ps1 -Port 4194` memeriksa preview lokal dan endpoint pengaturan Auth Supabase tanpa mencetak publishable key atau membuat akun/mengirim OTP.

Pemeriksaan terbaru endpoint pengaturan Auth menghasilkan HTTP 200 dengan phone dan email provider aktif. Login lewat SDK telah diperiksa menggunakan respons `invalid_credentials` yang diintersep di browser; pesan layanan belum terhubung tidak muncul. Login dengan kredensial asli dan pengiriman OTP/SMS belum diuji. App mendukung signup yang langsung memperoleh session maupun alur verifikasi 6 digit tanpa session, serta permintaan ulang dengan jeda 60 detik. Tidak ada perubahan pengaturan Auth selama perbaikan koneksi ini.

Tes memakai mock HTTP untuk memeriksa request/response Auth Supabase, mapping nomor belum terverifikasi, OTP, rate limit, dan sesi; tidak membuat akun atau mengirim SMS. Pemeriksaan jaringan saat ini mencakup endpoint pengaturan Auth dan request SDK yang diintersep. Android mengizinkan akses jaringan melalui permission INTERNET.

## Struktur

Kode dikelompokkan menurut fitur. Auth memakai Cubit karena saat ini alurnya form dan operasi submit. Bloc untuk sesi berlayar ditambahkan ketika fitur tersebut mulai dikerjakan.

`design/` menyimpan konteks Figma dan manifest sumber aset. File di folder itu boleh berisi URL unduhan Figma untuk provenance; runtime aplikasi memakai aset lokal dalam `assets/`. Status bar dan home indicator memakai sistem platform; tidak menggambar ulang screenshot OS sebagai bagian UI.

Font DM Sans dibundel lokal dengan lisensi OFL di `assets/fonts/`. Logo, foto, dan ikon mengikuti aset Figma yang diberikan pengguna.

## Hasil verifikasi slice autentikasi awal pada 16 Oktober 2026

Flutter 3.47.7 / Dart 3.13.5 dari instalasi lokal berhasil dijalankan di laptop ini; Edge terdeteksi. Android SDK belum tersedia.

- `flutter analyze`: tidak ada issue.
- `flutter test --reporter expanded`: 22 tes lulus, termasuk kontrak HTTP Supabase, OTP, pemulihan sesi, logout, keyboard/text scaling, navigasi, timer splash, dan proteksi submit ganda.
- `flutter build web -t tool/preview.dart --dart-define-from-file=config/supabase.local.json --no-web-resources-cdn`: build preview dengan konfigurasi lokal berhasil.
- Pemeriksaan browser pada `http://127.0.0.1:4187` memverifikasi Welcome, Login, Create Account, serta penanganan Phone Auth yang belum aktif. Screenshot baru memakai awalan `supabase-`; laporan `migration-verification.json` dan screenshot lainnya berasal dari pemeriksaan slice sebelumnya. Alur OTP live belum diverifikasi.

Perintah build web dapat memberi informasi tree-shaking dan referensi font Cupertino dari framework. Ikon layar yang diminta memakai SVG Figma lokal. Build APK/perilaku native Android belum diverifikasi.

## Alternatif tanpa SDK lokal

Status CI tersedia pada tab Actions repository. Hasil verifikasi lokal tercatat di `qa/migration-verification.json`. Workflow GitHub Actions monorepo di root menjalankan dependency resolution, analyze, test, dan build web dari `frontend/mobile`, lalu menyimpan artifact web.

Referensi: [Flutter web](https://docs.flutter.dev/platform-integration/web/building), [instalasi manual](https://docs.flutter.dev/install/manual), [continuous delivery](https://docs.flutter.dev/deployment/cd).

## Slice peta — Tanpa Pemantauan Focus 1–3

Layar mengikuti frame Figma terbaru 430 × 932 pada **High-Fidelity → mobile screen**: Focus 1 `194:749`, Focus 2 `194:1076`, dan Focus 3 `194:1014`. Focus 1 memperbarui ikon lokasi dan peta serta posisi panel. Focus 2 mengonfirmasi keberangkatan dan menyediakan Edit. Focus 3 memilih titik penangkapan tersendiri. Ikon ikan mengikuti aset dan animasi loop 2 detik dari Figma, dengan dukungan pengaturan reduced motion. Konteks desain, manifest aset, dan sumber motion disimpan di `design/untracked/`.

Aset ikon berasal dari Figma; gambar peta diganti OpenStreetMap sesuai permintaan. Implementasi mengikuti struktur fitur `lib/src/map/{domain,data,presentation}` dengan Cubit dan repository. Label lokasi memakai koordinat pilihan pengguna dan nama generik titik; nama pelabuhan contoh Figma tidak dipakai sebagai hasil geocoding. Garis putus-putus menghubungkan keberangkatan dan pilihan tujuan secara langsung, bukan hasil perhitungan rute laut.

Jalankan preview lalu buka `/?screen=departure`. Tambahkan `&demo-grid-locks=1` untuk dua contoh lock yang diberi label **data demo**. Mode normal membaca RPC Supabase bila tersedia; layanan yang belum terhubung menghasilkan status petak belum terverifikasi, tanpa lock buatan. Titik dipilih lewat GPS satu kali atau ketukan peta setelah menekan **Lihat Peta**, kemudian disimpan lokal per akun melalui SharedPreferences. Penyimpanan ini belum menyinkronkan titik ke backend.

Grid **statis 500 × 500 meter**, sesuai resolusi dataset pelatihan model yang dipilih pengguna. `MetricGrid500` memakai UTM 49S (EPSG:32749), origin `(0,0)`, namespace `tp-id-utm49s-500m:v2`, dan bounds `[112.25, -9.15, 113.10, -8.35]`. Admin dapat me-lock atau membuka lock petak; ukuran grid tidak dapat diubah melalui aplikasi maupun RPC admin. ID tidak berubah mengikuti zoom atau posisi kamera. Maksimal 600 kandidat petak diproses per viewport; saat zoom terlalu jauh aplikasi meminta pengguna memperbesar peta. Grid adalah indeks spasial dan dapat melintasi daratan; belum ada coastline mask, routing, atau penilaian kelayakan lokasi menangkap ikan.

Petak terkunci tetap digambar dengan warna dan ikon kunci. Focus 3 menolak penyimpanan tujuan **menangkap ikan** pada petak terkunci atau belum terverifikasi; status backend dimuat ulang sebelum menyimpan. Tombol **Muat ulang status** memungkinkan percobaan ulang sambil mempertahankan titik pilihan. Titik **keberangkatan** tetap boleh disimpan dengan alasan pembatasan ditampilkan. Snapshot kadaluwarsa mempertahankan lock yang diketahui, sedangkan petak lain menjadi unknown. Data demo tidak menyatakan petak lain terbuka.

Tombol **Selesai** menyimpan pilihan titik penangkapan lokal per akun, terpisah dari titik keberangkatan, dan memberi callback untuk tahap berikutnya. Catatan ini adalah pilihan rencana, bukan bukti aktivitas menangkap ikan atau hasil tangkapan. Form perjalanan setelah Focus 3 belum termasuk slice ini. Penyimpanan lokal bukan sinkronisasi backend; konfigurasi backend dan autentikasi tetap memakai implementasi sebelumnya.

Kontrak berada di `../../contracts/grid-locks.md`. Backend Supabase memakai grid 500 m tetap dan snapshot lock. Perubahan grid dinamis dibatalkan atas permintaan pengguna; migrasi pemulihan menghapus RPC create/preview/publish grid serta draft 1 km, dan membatasi ukuran pada 500 m di database. Riwayat migrasi yang sudah diterapkan tetap disimpan. Belum ada panel admin dan tidak ada membership admin yang ditetapkan, sesuai pilihan pengguna.

Titik tersimpan mencakup koordinat, ID petak 500 m, dan waktu simpan. Data 500 m yang sudah tersimpan tetap dapat dibaca; tidak ada tombol pergantian ukuran atau pemetaan ulang grid. Catatan dengan identitas grid lain tidak boleh ditafsirkan diam-diam sebagai petak 500 m.

Basemap saat ini memakai tile publik OSM secara online dengan atribusi yang dapat dibuka dan tanpa unduhan area/bulk. Fitur peta offline memerlukan paket data dan penyedia tile yang mengizinkannya; belum termasuk slice ini. GPS tidak melacak perjalanan di latar belakang. Izin lokasi Android telah ditambahkan, tetapi Android SDK belum tersedia untuk menguji APK dan permission native.

Hasil verifikasi grid statis dicatat di `qa/departure/verification.json`. QA Edge di `qa/departure/` memeriksa live OSM, pemilihan manual, simpan/buka ulang, GPS dengan fixture browser, dan status unknown saat belum login. QA koneksi berada di `qa/auth-connection/`. Fixture GPS, kredensial uji yang diintersep, dan lock demo bukan data lapangan.

Verifikasi Focus 1–3 berada di `qa/focus/`: screenshot 430 × 932 dan 360 × 640 serta skrip Edge Playwright dengan fixture GPS dan respons kebijakan yang diintersep. Pemeriksaan Flutter pada 16 Oktober 2026: 58 tes lulus, analyze tanpa issue, dan build preview web dengan konfigurasi lokal berhasil. Tes mencakup ketiga panel pada text scale 1.3, callback penyimpanan tanpa duplikasi, perubahan/ketidaktersediaan status petak saat submit, penyimpanan terpisah, serta loop animasi dan reduced motion. Android native tetap belum diverifikasi.

## Integrasi Flutter Map Handoff v2

Peta keberangkatan memakai seluruh snapshot dalam paket pengguna: 31.354 petak dengan nilai ikan, suhu laut, dan kedalaman, 140 fitur coral, tiga fitur mangrove, serta 24 berkas klorofil-a. Aset disimpan di `assets/geodata/`; ukuran seluruh aset geodata sekitar 31,4 MB. Salinan laporan audit dan manifest hash berada di `design/marine/`. Paket tidak menyertakan konfirmasi penyedia asli, lisensi data, satuan, atau waktu pengamatan CSV. Integrasi ini tidak menyatakan bahwa kualitas ilmiah atau hak redistribusi data sudah diverifikasi.

Indeks lokal paket diterjemahkan ke grid tetap aplikasi: `row = grid_y + 17975`, `col = grid_x + 1274`. Origin paket `(637500,8988000)` merupakan offset bulat dari grid EPSG:32749 berukuran 500 m; tidak ada identitas grid baru, perubahan lock, atau migrasi backend pada integrasi ini. Posisi tanpa baris CSV tetap NoData dan tidak diberi nilai nol. Garis grid dapat dimatikan tanpa mematikan warna layer maupun tanda lock.

Tombol **Lapisan peta** membuka pilihan satu layer numerik, coral kode 1 sebagai filter sementara, mangrove 2023, transparansi, dan garis grid. Klorofil nonaktif pada awalnya; pengguna dapat memilih urutan ekspor 1–24. Nomor tersebut tidak ditafsirkan sebagai waktu/bulan, dan 24 nilainya tidak dirata-ratakan. Rentang warna mengikuti snapshot sumber, bukan ambang aman, kelayakan menangkap, atau klasifikasi ilmiah.

Mengetuk peta tetap memilih titik melalui alur keberangkatan/penangkapan yang ada, sekaligus langsung membuka **Detail petak**. Semua kategori parameter ditampilkan terlepas dari layer aktif. Panel mencantumkan nilai, berkas sumber, identitas grid, status lock, ketidaktersediaan metadata, serta seluruh urutan klorofil yang dapat diperluas. Detail coral dan mangrove diperoleh dari irisan poligon lengkap dengan footprint petak, termasuk holes dan persinggungan batas. Atribut luas merujuk ke seluruh poligon sumber, bukan luas tutupan petak; tidak ada fitur yang cocok bukan bukti ketiadaan di lapangan. Kode coral 0/1 tetap mentah karena kamus kelas belum tersedia.

`AssetMarineRepository` membaca aset lokal, melakukan join dan validasi koordinat, serta menyimpan maksimal dua bagian klorofil dalam cache. `MarineMapCubit` memisahkan pilihan layer dari metadata petak, menolak hasil permintaan lama, membatasi pembacaan klorofil menjadi tiga sekaligus, dan menyimpan hasil detail lima petak terakhir. Parsing menggunakan `compute` pada platform yang mendukung isolate; pada Flutter web pekerjaan tersebut tetap berjalan di thread utama. Membuka detail pertama memuat 24 bagian klorofil; kinerja dan konsumsi memori native perlu diukur di perangkat sasaran.

Data parameter yang dibundel dapat dibaca tanpa jaringan; **basemap OSM tetap online**. Unduhan tile offline dan routing tidak ditambahkan oleh integrasi ini.

Verifikasi integrasi pada 16 Oktober 2026: `flutter analyze` tanpa issue, seluruh 79 tes Flutter lulus, dan `flutter build web -t tool/preview.dart --no-web-resources-cdn` berhasil. QA Edge di `qa/marine/` memeriksa data aset dan tile OSM berstatus 200, metadata semua kategori saat scalar nonaktif, pemuatan 24 bagian klorofil, kelanjutan konfirmasi simpan keberangkatan, serta tampilan 430 × 932 dan 360 × 640. Browser tidak mencatat page error atau console error. Tes widget juga memeriksa text scale 1.3, data kosong dengan fitur habitat, retry, serta ekspansi seluruh entri. Pengujian APK/native belum dilakukan.

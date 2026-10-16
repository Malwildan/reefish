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

`.\scripts\preview.ps1` memakai `config/supabase.local.json` bila tersedia untuk menjalankan preview dan mengaktifkan bootstrap yang sama dengan aplikasi utama. Jalankan aplikasi pada perangkat atau emulator dengan `.\scripts\run.ps1`; opsi `-Device` dan `-FlutterPath` tersedia. Status sesi dipulihkan oleh SDK, dipantau di atas route navigator, dan dibersihkan saat logout. Daftar tanpa sesi hanya membuka form verifikasi; sesi tidak dianggap berhasil sampai Supabase mengembalikan session. Setelah masuk, alur Journey mengikuti `api_me.next_step`: data kapal, perjalanan pertama, atau Dashboard. Status backend Journey dan batas verifikasi dijelaskan pada bagian Create Journey di bawah.

Session native kini memakai `flutter_secure_storage` 11.2.0 melalui adapter `SecureSessionLocalStorage`. Password tidak disimpan. Session Supabase yang sebelumnya berada di SharedPreferences dimigrasikan menggunakan key proyek yang sama; salinan lama baru dihapus setelah hasil tulis secure storage dibaca dan cocok. Marker migrasi mempertahankan salinan lama sebagai sumber pemulihan jika proses gagal. Operasi baca/tulis/hapus diurutkan agar penulisan token yang masih berjalan tidak memunculkan kembali session setelah logout.

Persistence dan refresh token SDK diaktifkan secara eksplisit. Saat startup, SDK membaca session sebelum aplikasi tampil; pengguna dengan session tersimpan langsung melanjutkan alur akun. Refresh token normal maupun gangguan jaringan sementara tidak mereset halaman/form. Login akun lain mengganti route agar state akun sebelumnya dibuang dari memori; draft lokal tetap terpisah per akun. Session yang dicabut/tidak valid memerlukan login kembali.

Flutter web tetap memakai localStorage bawaan SDK. Pemulihan hanya berlaku pada origin dan profil browser yang sama: mengganti domain tunnel, host, port, atau browser tidak memindahkan session. Android mempertahankan minimum SDK Flutter dengan batas bawah API 23 dan menonaktifkan Auto Backup untuk mencegah pemulihan ciphertext tanpa kunci perangkat. Runner iOS belum tersedia dalam repo; pengujian Keychain/iOS menunggu runner tersebut. Tidak ada perubahan RPC, provider Auth, atau pengaturan session server.

Verifikasi session pada 16 Oktober 2026: seluruh 200 tes Flutter lulus setelah integrasi dengan commit `1bfb443`; 14 tes baru mencakup migrasi, kegagalan penyimpanan, operasi logout yang berurutan, pemulihan saat startup, pergantian akun, dan refresh/error tanpa reset route. Analisis khusus auth bersih, dan build preview web berhasil. Analisis seluruh `lib test tool` juga bersih pada versi gabungan. Tes draft Journey memakai waktu payload untuk validasi agar konsisten dengan fixture yang mengikuti jam saat ini. QA browser di `qa/session/` memakai akun/respons sintetis yang diintersep, memeriksa satu password grant setelah login dan reload, refresh token kedaluwarsa, kegagalan jaringan tanpa logout, serta logout lalu reload tanpa session muncul kembali. Uji native tutup/buka proses belum dilakukan karena tidak ada perangkat Android terhubung.

Build APK debug berhasil dengan Temurin JDK 21 melalui `JAVA_HOME` hanya untuk proses build, tanpa mengubah konfigurasi Java global. Pada mesin Windows ini, cache Kotlin untuk plugin pada drive C: dan proyek pada drive D: gagal ditutup. Pemeriksaan build memakai Gradle secara langsung dengan `--no-daemon -Pkotlin.incremental=false -Pkotlin.compiler.execution.strategy=in-process`; konfigurasi build standar repositori tetap dipertahankan. Java 26 menghasilkan kegagalan `JdkImageTransform` pada dependency Android. APK uji berada di `build/app/outputs/flutter-apk/app-debug.apk`; hasil build bukan bukti uji tutup/buka aplikasi pada perangkat.

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

Jalankan `.\scripts\preview.ps1 -Port 4201` lalu buka `/?screen=departure`. Script memuat konfigurasi lokal Supabase saat tersedia. RPC status petak memerlukan sesi login; membuka URL peta langsung tidak membuat sesi. Pada kondisi belum login, tombol **Masuk untuk verifikasi** membuka form login. Konfigurasi yang belum tersedia, sesi login, izin akun, koneksi, dan respons tidak valid memiliki pesan terpisah. Muat ulang halaman tidak dapat memperbaiki konfigurasi build yang hilang; hentikan dan jalankan ulang preview dengan konfigurasi. Tambahkan `&demo-grid-locks=1` untuk dua contoh lock yang diberi label **data demo**. Titik dipilih lewat GPS satu kali atau ketukan peta setelah menekan **Lihat Peta**, kemudian disimpan lokal per akun melalui SharedPreferences. Penyimpanan ini belum menyinkronkan titik ke backend.

Grid **statis 500 × 500 meter**, sesuai resolusi dataset pelatihan model yang dipilih pengguna. `MetricGrid500` memakai UTM 49S (EPSG:32749), origin `(0,0)`, namespace `tp-id-utm49s-500m:v2`, dan bounds `[112.25, -9.15, 113.10, -8.35]`. Admin dapat me-lock atau membuka lock petak; ukuran grid tidak dapat diubah melalui aplikasi maupun RPC admin. ID tidak berubah mengikuti zoom atau posisi kamera. Maksimal 600 kandidat petak diproses per viewport; saat zoom terlalu jauh aplikasi meminta pengguna memperbesar peta. Grid adalah indeks spasial dan dapat melintasi daratan; belum ada coastline mask, routing, atau penilaian kelayakan lokasi menangkap ikan.

Petak terkunci tetap digambar dengan warna dan ikon kunci. Focus 3 menolak penyimpanan tujuan **menangkap ikan** pada petak terkunci atau belum terverifikasi; status backend dimuat ulang sebelum menyimpan. Tombol **Muat ulang status** memungkinkan percobaan ulang sambil mempertahankan titik pilihan ketika status gagal dimuat. Sesi yang tidak tersedia menawarkan login, sedangkan layanan yang belum dikonfigurasi tidak menawarkan retry tanpa hasil. Kegagalan refresh juga menolak penggunaan petak terbuka dari cache sampai refresh berhasil. Titik **keberangkatan** tetap boleh disimpan dengan alasan pembatasan ditampilkan. Snapshot kadaluwarsa mempertahankan lock yang diketahui, sedangkan petak lain menjadi unknown. Data demo tidak menyatakan petak lain terbuka.

Tombol **Selesai** menyimpan pilihan titik penangkapan lokal per akun, terpisah dari titik keberangkatan, dan memberi callback untuk tahap berikutnya. Catatan ini adalah pilihan rencana, bukan bukti aktivitas menangkap ikan atau hasil tangkapan. Form perjalanan setelah Focus 3 belum termasuk slice ini. Penyimpanan lokal bukan sinkronisasi backend; konfigurasi backend dan autentikasi tetap memakai implementasi sebelumnya.

Kontrak berada di `../../contracts/grid-locks.md`. Backend Supabase memakai grid 500 m tetap dan snapshot lock. Perubahan grid dinamis dibatalkan atas permintaan pengguna; migrasi pemulihan menghapus RPC create/preview/publish grid serta draft 1 km, dan membatasi ukuran pada 500 m di database. Riwayat migrasi yang sudah diterapkan tetap disimpan. Belum ada panel admin dan tidak ada membership admin yang ditetapkan, sesuai pilihan pengguna.

Titik tersimpan mencakup koordinat, ID petak 500 m, dan waktu simpan. Data 500 m yang sudah tersimpan tetap dapat dibaca; tidak ada tombol pergantian ukuran atau pemetaan ulang grid. Catatan dengan identitas grid lain tidak boleh ditafsirkan diam-diam sebagai petak 500 m.

Basemap saat ini memakai tile publik OSM secara online dengan atribusi yang dapat dibuka dan tanpa unduhan area/bulk. Fitur peta offline memerlukan paket data dan penyedia tile yang mengizinkannya; belum termasuk slice ini. GPS tidak melacak perjalanan di latar belakang. Izin lokasi Android telah ditambahkan, tetapi Android SDK belum tersedia untuk menguji APK dan permission native.

Hasil verifikasi grid statis dicatat di `qa/departure/verification.json`. QA Edge di `qa/departure/` memeriksa live OSM, pemilihan manual, simpan/buka ulang, GPS dengan fixture browser, dan status unknown saat belum login. QA koneksi berada di `qa/auth-connection/`. Fixture GPS, kredensial uji yang diintersep, dan lock demo bukan data lapangan.

Verifikasi Focus 1–3 berada di `qa/focus/`: screenshot 430 × 932 dan 360 × 640 serta skrip Edge Playwright dengan fixture GPS dan respons kebijakan yang diintersep. Pemeriksaan Flutter pada 16 Oktober 2026: 58 tes lulus, analyze tanpa issue, dan build preview web dengan konfigurasi lokal berhasil. Tes mencakup ketiga panel pada text scale 1.3, callback penyimpanan tanpa duplikasi, perubahan/ketidaktersediaan status petak saat submit, penyimpanan terpisah, serta loop animasi dan reduced motion. Android native tetap belum diverifikasi.

## Integrasi Flutter Map Handoff v2

Bagian berikut mendokumentasikan integrasi data peta yang sudah ada; slice Journey dijelaskan setelahnya.

Peta keberangkatan memakai seluruh snapshot dalam paket pengguna: 31.354 petak dengan nilai ikan, suhu laut, dan kedalaman, 140 fitur coral, tiga fitur mangrove, serta 24 berkas klorofil-a. Aset disimpan di `assets/geodata/`; ukuran seluruh aset geodata sekitar 31,4 MB. Salinan laporan audit dan manifest hash berada di `design/marine/`. Paket tidak menyertakan konfirmasi penyedia asli, lisensi data, satuan, atau waktu pengamatan CSV. Integrasi ini tidak menyatakan bahwa kualitas ilmiah atau hak redistribusi data sudah diverifikasi.

Indeks lokal paket diterjemahkan ke grid tetap aplikasi: `row = grid_y + 17975`, `col = grid_x + 1274`. Origin paket `(637500,8988000)` merupakan offset bulat dari grid EPSG:32749 berukuran 500 m; tidak ada identitas grid baru, perubahan lock, atau migrasi backend pada integrasi ini. Posisi tanpa baris CSV tetap NoData dan tidak diberi nilai nol. Garis grid dapat dimatikan tanpa mematikan warna layer maupun tanda lock.

Tombol **Lapisan peta** membuka pilihan satu layer numerik, coral kode 1 sebagai filter sementara, mangrove 2023, transparansi, dan garis grid. Klorofil nonaktif pada awalnya; pengguna dapat memilih urutan ekspor 1–24. Nomor tersebut tidak ditafsirkan sebagai waktu/bulan, dan 24 nilainya tidak dirata-ratakan. Rentang warna mengikuti snapshot sumber, bukan ambang aman, kelayakan menangkap, atau klasifikasi ilmiah.

Mengetuk peta tetap memilih titik melalui alur keberangkatan/penangkapan yang ada, sekaligus membuka popup ringkas dengan enam parameter dalam dua kolom, label baris/kolom petak, dan status lock. Panel bawah dipadatkan selama popup terbuka. Tombol **Detail data** membuka dialog tengah berisi metadata lengkap, berkas sumber, ID grid, kebijakan akses, serta seluruh urutan klorofil yang dapat diperluas. Popup dapat ditutup tanpa menutup route peta atau menghapus pilihan titik. Semua kategori parameter tetap tersedia terlepas dari layer aktif, dengan isi yang dapat digulir pada layar kecil. Detail coral dan mangrove diperoleh dari irisan poligon lengkap dengan footprint petak, termasuk holes dan persinggungan batas. Atribut luas merujuk ke seluruh poligon sumber, bukan luas tutupan petak; tidak ada fitur yang cocok bukan bukti ketiadaan di lapangan. Kode coral 0/1 tetap mentah karena kamus kelas belum tersedia.

Saat zoom jauh melewati batas 600 kandidat petak, garis putus-putus menandai extent area grid yang dikonfigurasi. Garis ini adalah batas jendela aplikasi, bukan batas administrasi, zona konservasi, mask laut, atau izin menangkap. Tombol garis grid juga mengatur tampilan batas ini; ukuran dan identitas petak tetap 500 m.

Pemilihan petak memakai satu entri klorofil untuk ringkasan, dipreload setelah data dasar siap dan dicache lintas petak pada instance peta yang sama. Seluruh 24 entri baru dimuat saat Detail data dibuka. Lookup coral/mangrove memakai bounding box yang disiapkan sekali dan cache LRU 128 petak; koordinat render habitat juga digunakan ulang. Cache ini tidak menyimpan keputusan lock atau menggantikan validasi backend. Hasil benchmark sebelum/sesudah dan batas pengukurannya berada di `qa/selection-performance/`.

`AssetMarineRepository` membaca aset lokal, melakukan join dan validasi koordinat, serta menyimpan maksimal dua bagian klorofil dalam cache. `MarineMapCubit` memisahkan pilihan layer dari metadata petak, menolak hasil permintaan lama, membatasi pembacaan klorofil menjadi tiga sekaligus, dan menyimpan hasil detail lima petak terakhir. Parsing menggunakan `compute` pada platform yang mendukung isolate; pada Flutter web pekerjaan tersebut tetap berjalan di thread utama. Membuka detail pertama memuat 24 bagian klorofil; kinerja dan konsumsi memori native perlu diukur di perangkat sasaran.

Data parameter yang dibundel dapat dibaca tanpa jaringan; **basemap OSM tetap online**. Unduhan tile offline dan routing tidak ditambahkan oleh integrasi ini.

Verifikasi integrasi pada 16 Oktober 2026: `flutter analyze` tanpa issue, seluruh 79 tes Flutter lulus, dan `flutter build web -t tool/preview.dart --no-web-resources-cdn` berhasil. QA Edge di `qa/marine/` memeriksa data aset dan tile OSM berstatus 200, metadata semua kategori saat scalar nonaktif, pemuatan 24 bagian klorofil, kelanjutan konfirmasi simpan keberangkatan, serta tampilan 430 × 932 dan 360 × 640. Browser tidak mencatat page error atau console error. Tes widget juga memeriksa text scale 1.3, data kosong dengan fitur habitat, retry, serta ekspansi seluruh entri. Pengujian APK/native belum dilakukan.

## Create Journey → Dashboard

Slice mengikuti konteks Figma terbaru pada 16 Oktober 2026: **Create Journey `194:810`** dan **Dashboard `104:80`**. Sumber konteks dan manifest aset ada di `design/journey/`. Form memakai logo dan ikon kembali lokal yang sama dengan Auth. Dashboard memakai kompas, ikon cuaca, kartu rekomendasi, dan navigasi bawah dari aset desain. Basemap diganti OSM online dengan atribusi selalu terlihat; grid tetap 500 × 500 m.

Alur setelah login membaca profil dan `next_step` dari backend: kapal → perjalanan pertama → Dashboard. Form kapal merupakan prasyarat backend. Form perjalanan mengumpulkan BBM, berat tangkapan, tanggal serta jam WIB, dan pilihan lokasi dari peta. Jam berangkat/pulang tetap harus diisi pengguna; menit awal adalah nilai nyata `00`, dengan hint `JJ`/`MM` saat kolom kosong. Menit yang sengaja dihapus harus diisi kembali. Jam pulang lebih awal berarti hari berikutnya dan ditampilkan secara eksplisit. Waktu dikirim sebagai UTC. Waktu keberangkatan/pulang tidak disalin menjadi durasi menangkap ikan.

Struktur fitur `journey/{domain,data,presentation}` memakai Cubit dan repository. Adapter Supabase mengikuti kontrak GitHub branch `gipar`, yang disalin ke `contracts/nelayan-api.openapi.yaml`; hasil audit ada di `design/journey/backend-audit.md`. Tidak ada migrasi backend, perubahan role, atau perubahan identitas grid pada slice ini. Server menerima koordinat WGS84 dan menentukan cell ML sendiri.

Sebelum request perjalanan, payload disimpan per akun dengan UUID yang tetap. Retry memakai payload dan UUID yang sama. Setelah ACK, kegagalan memuat Dashboard tidak memicu submit ulang. Ini satu draft pending memakai SharedPreferences, **belum outbox SQLite untuk sesi berlayar/offline penuh**. Data ditolak backend bisa diperbaiki melalui tindakan eksplisit; error jaringan mempertahankan payload pending.

Backend Journey Supabase kini aktif. Lima RPC (`api_me`, `api_create_boat`, `api_post_trip`, `api_list_trips`, `api_trip_detail`) sudah tersedia; request anonim ditolak dan request pengguna memeriksa kepemilikan data. Verifikasi integrasi memakai transaksi rollback dan mencakup pembuatan kapal/perjalanan, retry dengan UUID yang sama, riwayat, detail, serta akses lintas akun. Hasil dan batas verifikasi tercatat di `design/journey/backend-audit.md`.

Go API kini tersedia di `backend/api` setelah branch `gipar` digabung ke `main`. Preview lokal dikonfigurasi dengan `REEFISH_API_URL` melalui berkas lokal yang diabaikan Git. Deployment backend permanen belum dibuat; tunnel preview hanya aktif selama proses dan komputer pengembang berjalan. Prediksi belum diimpor, sehingga rekomendasi dan BBM prediksi belum siap. Kegagalan rekomendasi tidak menghalangi pemuatan cuaca. Rekomendasi tanpa masa berlaku aktif tidak ditampilkan sebagai rekomendasi aktif. Auth tetap memakai Supabase phone/password.

Cuaca Dashboard memakai koordinat pelabuhan kapal dan JWT Supabase pengguna melalui Go `/api/v1/weather`. Suhu ditampilkan dalam °C, angin dikonversi dari m/s ke km/jam, dan gelombang dalam meter. Nilai kosong tetap tidak diketahui (`—`), bukan nol. Dashboard menampilkan waktu prakiraan, waktu respons dimuat, serta tautan sumber Open-Meteo dan DWD. Tanpa koordinat pelabuhan, pengguna diminta melengkapinya.

Untuk menjalankan backend di PowerShell dari root repositori:

```powershell
.\backend\scripts\run-api.ps1 -GoPath go -AllowedOrigin http://127.0.0.1:4195
```

Helper membaca URL/key publik Supabase dari `config/supabase.local.json`. Tambahkan `REEFISH_API_URL` yang mengarah ke layanan tersebut pada berkas konfigurasi yang sama, lalu build ulang Flutter dengan `--dart-define-from-file=config/supabase.local.json`. Flutter native memerlukan alamat backend yang dapat dijangkau perangkat; `127.0.0.1` hanya menunjuk perangkat itu sendiri. Preview HTTPS memerlukan backend HTTPS. Untuk preview lintas origin sementara, helper menerima `-AllowedOrigin '*'`; deployment permanen sebaiknya memakai origin web yang tepat.

Verifikasi integrasi cuaca: 152 tes Flutter lulus, `flutter analyze lib test tool` bersih, dan build preview web berhasil. `flutter analyze` seluruh folder masih menemukan masalah pada contoh terpisah `examples/peta_laut` dari branch gabungan; contoh tersebut tidak dibangun oleh aplikasi utama. Tes dan vet Go lulus. Adapter Go juga diuji langsung terhadap Open-Meteo. QA browser di `qa/weather/` memakai respons Auth/profil/cuaca/rekomendasi yang diintersep; ini bukan bukti alur cuaca penuh dengan akun produksi. Perangkat Android belum diuji.

Preview langsung: `/?screen=journey` atau `/?screen=dashboard`. Keduanya tetap memerlukan sesi dan backend; query URL tidak membuat sesi/data contoh. Dari peta Focus 3, **Selesai** meneruskan pilihan titik ke alur Journey. Expand Dashboard membuka peta baca-saja; navigasi profil membuka ringkasan akun dan logout. Pelacakan sesi berlayar belum termasuk slice ini.

Verifikasi: seluruh 134 tes Flutter lulus pada versi terakhir, termasuk tanggal WIB, retry idempoten, batas akun, kontrak RPC, dan data tidak tersedia. Tes Dashboard juga memeriksa 360 × 640 dengan text scale 1.3. Analyze bersih dan build preview web dengan konfigurasi lokal berhasil. QA Edge di `qa/journey/` mencakup Focus → kapal → form → gagal kirim → retry → Dashboard, reload tanpa submit ulang, dan viewport 430/360. Respons Auth/kapal/perjalanan/kebijakan diintersep sebagai fixture; tidak membuat data produksi. Tile OSM merespons 200. Native Android belum diuji karena SDK belum tersedia.

## Pembaruan status petak

Status lock Supabase berlaku lima menit. Peta memperbarui snapshot otomatis ketika masa berlakunya habis dan saat aplikasi kembali aktif. Setiap refresh memakai respons backend baru; kegagalan refresh menghentikan pembaruan otomatis sampai pengguna mencoba lagi, mempertahankan lock yang sudah diketahui, dan memblokir pemilihan titik ikan yang belum terverifikasi.

Adapter RPC mengukur waktu request dengan Stopwatch dan menghitung masa berlaku lokal dari TTL server dikurangi waktu request. Timestamp asli server tetap disimpan untuk metadata. Perbedaan jam perangkat/server tidak lagi membuat snapshot yang baru diterima dianggap belum berlaku; masa berlaku tidak diperpanjang melebihi TTL server. Payload yang diparse tanpa konteks penerimaan live tetap memakai timestamp absolutnya.

Saat status tidak tersedia, rincian petak membedakan loading, kegagalan koneksi/login, data demo, dan status kedaluwarsa. Nilai ikan/suhu/kedalaman/habitat merupakan data sumber yang terpisah dari status lock admin, sehingga tampilnya data tersebut tidak menyatakan lock telah diverifikasi.

Verifikasi pembaruan status pada 16 Oktober 2026: 142 tes Flutter lulus, analyzer tanpa issue, dan build web dengan konfigurasi Supabase lokal berhasil. Regresi mencakup clock skew, TTL yang habis selama request, parsing cache tanpa reset TTL, pembaruan otomatis, kegagalan refresh tanpa retry loop, dan pembaruan ketika aplikasi kembali aktif. QA browser memakai respons Auth/status sintetis yang diintersep; tidak mengubah akun atau lock produksi.

Perbaikan input waktu Journey: nilai menit awal `00` adalah isi kolom, bukan placeholder. Regresi 05:00–19:00 dengan menit tidak disentuh lulus. Delapan tes form lulus, analyzer bersih, build web berhasil, dan QA browser di `qa/journey-time/verification.json` memastikan menit kosong ditolak sebelum request serta pengiriman dengan menit 00 sampai Dashboard menggunakan respons backend uji yang diintersep.

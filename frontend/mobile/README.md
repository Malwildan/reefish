# Reefish mobile — auth slice

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

`.\scripts\preview.ps1` memakai `config/supabase.local.json` bila tersedia untuk menjalankan preview dan mengaktifkan bootstrap yang sama dengan aplikasi utama. Jalankan aplikasi pada perangkat atau emulator dengan `.\scripts\run.ps1`; opsi `-Device` dan `-FlutterPath` tersedia. Status sesi dipulihkan oleh SDK, dipantau di atas route navigator, dan dibersihkan saat logout. Daftar tanpa sesi hanya membuka form verifikasi; sesi tidak dianggap berhasil sampai Supabase mengembalikan session. Layar setelah masuk hanya mengonfirmasi sesi dan menyediakan logout, karena Dashboard belum dibuat.

Project saat ini belum mempunyai SMS provider. Pemeriksaan endpoint membaca bahwa phone auth/provider masih nonaktif, dan tidak ada pengguna atau SMS yang dibuat selama pemeriksaan. Karena itu, signup/login telepon sungguhan belum dapat berhasil sampai provider diaktifkan. Konfigurasi nomor uji dengan OTP tetap memerlukan provider SMS yang dikonfigurasi; test OTP Supabase bukan jalan tanpa provider untuk hosted project. Gunakan nomor khusus yang dikuasai tester; jangan mengarang nomor yang terlihat seperti nomor reserved. App mendukung signup yang langsung memperoleh session maupun alur verifikasi 6 digit tanpa session, serta permintaan ulang dengan jeda 60 detik. Phone confirmation tetap aktif; perubahan mode konfirmasi perlu disepakati.

Tes memakai mock HTTP untuk memeriksa request/response Auth Supabase, mapping nomor belum terverifikasi, OTP, rate limit, dan sesi; tidak membuat akun atau mengirim SMS. Koneksi live belum diuji untuk signup/login karena provider telepon belum aktif. Android mengizinkan akses jaringan melalui permission INTERNET.

## Struktur

Kode dikelompokkan menurut fitur. Auth memakai Cubit karena saat ini alurnya form dan operasi submit. Bloc untuk sesi berlayar ditambahkan ketika fitur tersebut mulai dikerjakan.

`design/` menyimpan konteks Figma dan manifest sumber aset. File di folder itu boleh berisi URL unduhan Figma untuk provenance; runtime aplikasi memakai aset lokal dalam `assets/`. Status bar dan home indicator memakai sistem platform; tidak menggambar ulang screenshot OS sebagai bagian UI.

Font DM Sans dibundel lokal dengan lisensi OFL di `assets/fonts/`. Logo, foto, dan ikon mengikuti aset Figma yang diberikan pengguna.

## Hasil verifikasi pada 16 Oktober 2026

Flutter 3.47.7 / Dart 3.13.5 dari instalasi lokal berhasil dijalankan di laptop ini; Edge terdeteksi. Android SDK belum tersedia.

- `flutter analyze`: tidak ada issue.
- `flutter test --reporter expanded`: 22 tes lulus, termasuk kontrak HTTP Supabase, OTP, pemulihan sesi, logout, keyboard/text scaling, navigasi, timer splash, dan proteksi submit ganda.
- `flutter build web -t tool/preview.dart --dart-define-from-file=config/supabase.local.json --no-web-resources-cdn`: build preview dengan konfigurasi lokal berhasil.
- Pemeriksaan browser pada `http://127.0.0.1:4187` memverifikasi Welcome, Login, Create Account, serta penanganan Phone Auth yang belum aktif. Screenshot baru memakai awalan `supabase-`; laporan `migration-verification.json` dan screenshot lainnya berasal dari pemeriksaan slice sebelumnya. Alur OTP live belum diverifikasi.

Perintah build web dapat memberi informasi tree-shaking dan referensi font Cupertino dari framework. Ikon layar yang diminta memakai SVG Figma lokal. Build APK/perilaku native Android belum diverifikasi.

## Alternatif tanpa SDK lokal

Status CI tersedia pada tab Actions repository. Hasil verifikasi lokal tercatat di `qa/migration-verification.json`. Workflow GitHub Actions monorepo di root menjalankan dependency resolution, analyze, test, dan build web dari `frontend/mobile`, lalu menyimpan artifact web.

Referensi: [Flutter web](https://docs.flutter.dev/platform-integration/web/building), [instalasi manual](https://docs.flutter.dev/install/manual), [continuous delivery](https://docs.flutter.dev/deployment/cd).

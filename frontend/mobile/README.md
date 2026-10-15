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
& "$env:USERPROFILE/develop/flutter/bin/flutter.bat" run -d edge
```

Untuk pemeriksaan:

```powershell
.\scripts\check.ps1
```

Script menjalankan dependency resolution, analisis, tes, dan build web. Preview web memeriksa UI/interaksi Flutter; build dan perilaku keyboard/status bar native Android tetap perlu diverifikasi pada perangkat Android nanti.

## Batas fungsi autentikasi

Ini slicing UI dan fondasi state. Repository default **belum terhubung ke layanan akun**. Input valid tidak membuat akun atau sesi sungguhan; submit menampilkan pesan bahwa layanan akun belum terhubung. Tidak ada kredensial yang ditulis ke disk atau log.

`AuthRepository` menjadi seam integrasi untuk Supabase selanjutnya; UI hanya berhubungan dengan AuthCubit dan hasil/error domain. Uji memakai repository palsu terkontrol sebagai fixture, bukan backend yang sudah tersedia.

Scope berhenti pada empat layar ini. Permissions serta Dashboard berada pada tahap berikutnya. Data contoh pada frame lain tidak diimplementasikan dalam slice ini.

## Struktur

Kode dikelompokkan menurut fitur. Auth memakai Cubit karena saat ini alurnya form dan operasi submit. Bloc untuk sesi berlayar ditambahkan ketika fitur tersebut mulai dikerjakan.

`design/` menyimpan konteks Figma dan manifest sumber aset. File di folder itu boleh berisi URL unduhan Figma untuk provenance; runtime aplikasi memakai aset lokal dalam `assets/`. Status bar dan home indicator memakai sistem platform; tidak menggambar ulang screenshot OS sebagai bagian UI.

Font DM Sans dibundel lokal dengan lisensi OFL di `assets/fonts/`. Logo, foto, dan ikon mengikuti aset Figma yang diberikan pengguna.

## Hasil verifikasi pada 16 Oktober 2026

Flutter 3.47.7 / Dart 3.13.5 dari instalasi lokal berhasil dijalankan di laptop ini; Edge terdeteksi. Android SDK belum tersedia.

- `flutter analyze`: tidak ada issue.
- `flutter test --reporter expanded`: 12 tes lulus, termasuk keyboard/text scaling, navigasi, timer splash, dan proteksi submit ganda.
- `flutter build web -t tool/preview.dart --no-web-resources-cdn`: build preview web berhasil.
- Screenshot browser diperiksa untuk empat layar dan tampilan 360 × 640; file bukti berada di `qa/`.

Perintah build web dapat memberi informasi tree-shaking dan referensi font Cupertino dari framework. Ikon layar yang diminta memakai SVG Figma lokal. Build APK/perilaku native Android belum diverifikasi.

## Alternatif tanpa SDK lokal

Status CI tersedia pada tab Actions repository. Hasil verifikasi lokal tercatat di `qa/migration-verification.json`. Workflow GitHub Actions monorepo di root menjalankan dependency resolution, analyze, test, dan build web dari `frontend/mobile`, lalu menyimpan artifact web.

Referensi: [Flutter web](https://docs.flutter.dev/platform-integration/web/building), [instalasi manual](https://docs.flutter.dev/install/manual), [continuous delivery](https://docs.flutter.dev/deployment/cd).

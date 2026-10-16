# QA pemulihan sesi pada Flutter web

`check-session.cjs` menjalankan preview Flutter di Edge headless. Login, refresh, dan logout memakai respons akun/sesi sintetis; semua request Supabase diintersep. Script memeriksa login melalui form, pemulihan pada reload origin sama, refresh sesi kedaluwarsa, kegagalan jaringan sementara tanpa logout, serta logout yang tetap bersih setelah reload. Ia memblokir endpoint Supabase tak dikenal dan request eksternal sebelum akses jaringan.

## Menjalankan

Pastikan preview web terbangun dan berjalan pada port 4195, lalu dari root repo:

```powershell
$env:NODE_PATH = 'C:\path\ke\node_modules'
$env:PREVIEW_URL = 'http://127.0.0.1:4195'
node frontend/mobile/qa/session/check-session.cjs
```

Script menyimpan `verification.json` dan screenshot berdampingan. Laporan berisi jumlah grant dan hasil penyimpanan tanpa session token atau publishable key.

## Bukti dan batas

Artefak saat ini menunjukkan semua lima skenario browser berhasil: [laporan](verification.json), termasuk [reload setelah login](restored-session-430.png), [refresh token](refreshed-session-430.png), [gangguan refresh](refresh-outage-430.png), dan [reload setelah logout](login-after-logout-reload-430.png). Ini membuktikan localStorage pada origin dan profil browser yang diuji.

Tes ini tidak menguji Android Keystore, iOS Keychain, kehilangan kunci perangkat, atau pemulihan proses native. Tes adapter Flutter dan build APK yang dilaporkan terpisah juga tidak menggantikan uji tutup/buka aplikasi fisik. Lihat [README mobile](../../README.md) untuk bukti integrasi dan batas rilis.

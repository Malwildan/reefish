# QA cuaca Dashboard

`check-weather.cjs` menguji tampilan Dashboard pada browser headless dengan fixture untuk Auth, profil, riwayat perjalanan, cuaca, dan rekomendasi. Request Go cuaca/rekomendasi diintersep; konfigurasi `GO_API_URL` harus cocok dengan URL yang dikompilasi agar request yang tidak diharapkan diblokir. Supabase URL dibaca dari konfigurasi lokal; kunci publik tidak dicetak/dimasukkan ke laporan.

## Menjalankan

Jalankan preview yang sudah dibangun dengan URL Go yang sama, lalu dari root repo:

```powershell
$env:NODE_PATH = 'C:\path\ke\node_modules'
$env:PREVIEW_URL = 'http://127.0.0.1:4195'
$env:GO_API_URL = 'https://your-api-host/api/v1'
node frontend/mobile/qa/weather/check-weather.cjs
```

Hasil tersimpan di `verification.json` bersama screenshot desktop dan viewport 360 × 640. Uji mencakup suhu, konversi angin, tinggi gelombang, atribusi Open-Meteo/DWD, nilai laut null, cuaca 503 tanpa angka usang, dan cuaca tetap tampil saat rekomendasi gagal.

## Bukti dan batas

Laporan browser saat ini tidak memiliki error, memuat status UI normal/null/error, serta mengukur `scrollWidth` 360 px pada viewport 360 px. Contoh tampilannya: [Dashboard normal](weather-430.png), [nilai laut null](weather-null-marine-430.png), [layanan gagal](weather-unavailable-430.png), dan [viewport ringkas](weather-360x640.png).

Semua respons browser adalah fixture, bukan login atau permintaan UI ke API live. Smoke check API/health, penolakan token anonim, CORS, dan panggilan provider Open-Meteo dicatat sebagai bukti terpisah dalam laporan integrasi. Pengujian tersebut tidak membuktikan satu sesi UI terautentikasi end-to-end. Tile peta tidak termasuk scope suite ini. Rekomendasi saat ini adalah fallback heuristik; bukan inferensi model ML terlatih atau jaminan hasil tangkapan.

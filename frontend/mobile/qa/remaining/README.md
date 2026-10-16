# QA visual layar sesi dan fitur tersisa

`tool/remaining_preview.dart` merender widget produksi dengan repository, izin, dan stream GPS sintetis di memori. Panel kontrol QA berada di luar batas gambar aplikasi; tile OSM yang terlihat adalah konteks jaringan nyata, bukan prediksi. Suite ini berguna untuk memeriksa tampilan layar yang belum memiliki QA terpisah, termasuk mode lokasi, sesi, izin, rekomendasi, profil, pengaturan, dan detail perjalanan.

## Menjalankan preview QA

Dari `frontend/mobile`:

```powershell
flutter build web -t tool/remaining_preview.dart --output build/remaining-qa --no-web-resources-cdn --no-wasm-dry-run
python qa/remaining/serve.py
```

Buka `http://127.0.0.1:4197/` (430 × 932) atau `http://127.0.0.1:4197/?width=360&height=640`. Aktifkan aksesibilitas Flutter untuk kontrol semantik browser. Panel QA dapat digulir; cek fase yang terlihat setelah tiap tindakan. Tombol capture mengirim PNG terbatas ke server loopback saja.

Gambar sumber dan manifest hash ada di `design/remaining/`. Laporan desain memberikan hasil visualisasi; screenshot tidak menyatakan integrasi backend.

## Bukti dan batas fungsi

Catatan suite terpilih: 195 tes lulus setelah mengecualikan `test/session_restore_test.dart`, yang hang pada run awal; tes yang terdampak perubahan visual dijalankan kembali. `flutter analyze lib tool` bersih. Hasil build/capture final dirujuk di laporan desain. Ini angka dari cakupan dan waktu pengujian yang tercatat, bukan hitungan total tes terbaru.

Sesi dapat dimulai, dijeda, dilanjutkan, dihentikan, dan diselesaikan dengan GPS sintetis. Ringkasan sesi dan titiknya tersimpan lokal. ACK pengiriman berasal dari repository palsu dalam memori. Jadi QA ini menguji perilaku komponen, bukan rekaman produksi. Alur Journey normal mengirim draft perjalanan ke Supabase secara online; sesi lokal belum mempunyai outbox dan sinkronisasi offline penuh.

Lihat [README mobile](../../README.md) untuk jalur demo utama dan [QA sesi autentikasi](../session/README.md) untuk batas browser/native.

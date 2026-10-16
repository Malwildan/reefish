# QA pemulihan kebijakan grid — 16 Oktober 2026

Perubahan ini memperjelas pesan ketika konfigurasi Supabase hilang, sesi tidak ada, izin ditolak, layanan gagal, atau payload tidak valid. Untuk pilihan titik menangkap ikan, status yang tidak diketahui tetap memblokir simpan; snapshot lama yang menyatakan sel terbuka tidak boleh melewati pemeriksaan baru. Sel terkunci tetap ditolak.

## Bukti

- Regresi repository memakai mock HTTP dengan Supabase client nyata untuk respons sukses dan kategori kegagalan.
- Tes Cubit mencakup sesi hilang setelah cache-open, pemilihan berulang, dan pemulihan setelah refresh berhasil.
- Tes widget memeriksa aksi masuk yang ditawarkan pada kondisi perlu autentikasi.
- Catatan uji pada laporan ini: 90 tes Flutter lulus, analyzer bersih, dan build preview web berhasil. Respons RPC anonim langsung mendapat HTTP 401 / kode PostgreSQL 42501; pengaturan Auth dapat dibaca HTTP 200. Tidak ada akun dibuat atau SMS dikirim.
- Artefak browser: [laporan percobaan](configured-auth-qa.json), [tampilan formulir masuk](configured-login-form-430.png), dan [tangkapan layar 360 px](configured-fishing-360.png).

## Batas bukti

Percobaan browser merekam lima ketukan, tetapi kelimanya jatuh pada ID sel yang sama (`fiveDistinctCellIds: false`); ini bukan bukti lima sel berbeda. Tes Cubit-lah yang mencakup pemilihan berbeda. Laporan browser juga mendeteksi lebar semantik 388 px pada viewport 360 px. Tampilan gambar terlihat muat, tetapi metrik overflow itu belum terselesaikan.

Skenario browser dalam catatan ini tidak menyimpan titik ikan dengan sesi backend nyata. Fixture HTTP, build web, dan HTTP 401 anonim membuktikan perilaku tertentu saja; semuanya bukan uji alur penangkapan terautentikasi dari UI. Periksa juga [QA freshness](../grid-freshness/) untuk perilaku masa berlaku snapshot dan [QA popup peta](../map-popup/README.md) untuk tampilan detail.

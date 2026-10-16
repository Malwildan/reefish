# Migrasi Supabase

File SQL berurutan adalah catatan perubahan skema dan source untuk instalasi baru. Migrasi grid awal, migrasi kompatibilitas Journey, lalu migrasi nelayan/zona/layer merupakan riwayat yang harus dipertahankan. Jangan mengedit migrasi yang sudah diterapkan untuk mengubah hosted; tambahkan migrasi maju dan sertakan tes SQL yang sesuai.

Rekap hosted 16 Oktober 2026 ada di [`../setup/integration-verification.json`](../setup/integration-verification.json). Di sana tercatat migrasi `20261016100600`–`20261016101100`, optimasi `20261016125501`, dan refresh asinkron `20261016130000` diterapkan. Ledger lingkungan lain dapat berbeda; verifikasi sebelum menjalankan `db push` atau perintah repair.

Grid tetap 500 × 500 m pada EPSG:32749. Draft dan uji desain dinamis tersimpan di [`../archive/`](../archive/README.md), bukan migrasi aktif. Tes SQL per kelompok ada di [`../tests/`](../tests/README.md); urutan impor dan batas SQL setup dijelaskan di [`../setup/README.md`](../setup/README.md).

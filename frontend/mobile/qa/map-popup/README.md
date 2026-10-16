# QA popup data petak dan batas cakupan — 16 Oktober 2026

Ketukan pada sel membuka popup putih di atas peta dengan enam kategori ringkasan, identitas grid, sumber, status lock, serta daftar 24 entri klorofil yang dapat diperluas. Popup dapat digulir pada ruang di atas panel alur. Menutup popup mempertahankan titik yang dipilih. Kunci sel pada state mencegah hasil permintaan lama tampil untuk sel baru.

Saat lebih dari 600 kandidat sel berada di viewport, persegi panjang garis putus-putus `[6,5]` memperlihatkan extent grid yang dikonfigurasi. Itu batas cakupan aplikasi, bukan batas hukum/administrasi, zona konservasi, atau mask laut.

## Bukti

- 93 tes Flutter tercatat lulus; cakupan termasuk popup pada 328 × 200 dengan text scale 1.3, callback tutup tanpa pop route, dan respons lama.
- Lima tes terkait diulang setelah penyesuaian overlay/atribusi; build preview web terakhir berhasil.
- Screenshot: [430 × 932](popup-430x932.png), [360 × 640](popup-360x640.png), dan [grid extent pada zoom jauh](low-zoom-grid-on-430x932.png). Laporan agregat disimpan di [map-popup-qa-summary.json](map-popup-qa-summary.json).

## Batas bukti

Probe browser pertama menemukan enam kategori sebelum dan sesudah scroll pendek serta tombol tutup. Probe scroll lebih dalam kemudian menulis `popup-360-qa.json` dengan `pass: false`, karena widget ListView mengeluarkan label yang berada di luar layar dari DOM semantik. Keadaan ini tidak membuktikan kategori tak dapat diakses; kedua laporan dipertahankan. Pengukuran DOM juga menunjukkan lebar scroll semantik lebih besar dengan posisi scroll tetap nol.

Harness browser gagal pada setup interaksi sel kedua. Jadi penggantian sel, gesture peta, dan toggle grid tidak dianggap lulus dari browser; penggantian state dan hasil usang tercakup pada tes widget. QA ini memakai preview signed-out dan tidak menguji simpan titik melalui akun live. Android/iOS native belum diuji pada perubahan ini.

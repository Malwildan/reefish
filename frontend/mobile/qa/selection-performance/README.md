# Kinerja pemilihan sel — 16 Oktober 2026

Ringkasan popup sebelumnya membaca semua 24 berkas klorofil saat sel baru dipilih. Perbaikannya memuat hanya entri ekspor yang dipakai ringkasan; preload terjadi setelah dataset dasar siap dan tidak menahan kesiapan peta. Detail lengkap tetap membaca 24 entri saat diminta. Batas baca bersamaan dan cache dipakai untuk data sumber. Cache ini tidak menyimpan status lock atau menggantikan validasi saat simpan.

## Pengukuran

`baseline.json` dan `after.json` menyimpan hasil benchmark dengan aset terbundel pada Flutter native VM; satuannya mengukur kerja data/domain dan file lokal, bukan frame rate browser atau latensi ketukan ponsel.

| Ukuran | Sebelum | Sesudah |
|---|---:|---:|
| Permintaan klorofil sel pertama | 2.473 ms | 157–268 ms pada dua run khusus; 282 ms pada suite |
| Sel berbeda berikutnya | 2.546 ms | <1 ms pada presisi ms yang direkam |
| Baca aset untuk dua/lima sel dan pengulangan | 48 baca untuk dua sel | 1 baca untuk lima sel dan satu pengulangan |
| Byte entry ringkasan dingin | 27.437.084 (24 file) | 1.143.150 (1 file) |

Waktu dipengaruhi beban mesin. Jumlah file yang dibaca lebih stabil untuk regresi daripada klaim waktu perangkat. Pengukuran geometri membandingkan strategi cache berbeda, sehingga hanya diagnostik pendukung.

## Pemeriksaan dan batas

Pada run yang dicatat, seluruh 134 tes Flutter lulus dan analyzer bersih. Tes meliputi reuse lintas sel, request bersamaan, preload tanpa blokir, retry, perubahan entry, detail penuh lazy, batas concurrency, nilai sumber, geometri polygon dan eviction cache. Screenshot [browser-summary.png](browser-summary.png) menunjukkan smoke check fungsi popup dan badge kebijakan; bukan pengukuran latensi UI end-to-end.

Build web preview yang dikonfigurasi berhasil, tetapi performa Android/iOS belum diukur pada perangkat. Cache hanya hidup selama instance peta; ini bukan unduhan tile/offline data persisten dan tidak menjamin data tersedia setelah aplikasi ditutup. Lihat [laporan audit data laut](../../design/marine/README.md) untuk makna dan kekurangan metadata sumber.

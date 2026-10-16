# Arsip rancangan dan pengujian lama

Isi direktori ini adalah bukti desain terdahulu, bukan migrasi atau pemeriksaan untuk kondisi sekarang. File `*_500m_draft*` merekam usulan awal; file `dynamic_grid_*` merekam desain grid dinamis yang sempat diuji dan kemudian diganti karena produk menggunakan sel 500 m tetap.

Jangan jalankan SQL arsip sebagai deployment atau smoke test. Skema sekarang ditentukan oleh migrasi berurutan di [`../migrations/`](../migrations/README.md), sedangkan uji yang relevan saat ini ada di [`../tests/`](../tests/README.md). Keputusan grid saat ini dipertegas dalam [`../../../contracts/grid-locks.md`](../../../contracts/grid-locks.md).

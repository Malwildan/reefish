# Pengujian ML dan data

Belum ada test runner atau suite pengujian ML yang ditetapkan di folder ini. Notebook menjalankan clustering secara interaktif, tetapi itu sendiri bukan suite pengujian yang dapat diulang. Pengujian yang kelak ditambahkan perlu memeriksa perilaku kode dan kesesuaian keluaran dengan kontrak; jangan menyamakan test struktur data atau skor silhouette tanpa label dengan validasi ilmiah model.

Prioritas uji yang sesuai dengan artefak saat ini:

- validasi schema, nilai numerik hingga, key dan urutan 31.354 sel, koordinat, serta batas AOI untuk persiapan geodata;
- kelengkapan 24 blok klorofil dan manifest hash, sambil mempertahankan fakta bahwa urutan berkas belum membuktikan sumbu waktu;
- kecocokan ID grid terhadap kontrak dan fixture bersama `../../contracts/grid-index.md` serta `../../contracts/fixtures/grid-index-vectors.json`;
- jika clustering notebook dipindahkan ke pipeline yang dapat dipakai ulang, uji schema input/output, kasus gagal, baseline, evaluasi holdout tanpa kebocoran waktu/lokasi, dan reproduksibilitas versi artefak.

Gunakan fixture sintetis atau sampel berizin. Jangan commit dataset, data pengguna, kredensial, bobot, maupun checkpoint. Laporkan tepat perintah dan hasil yang benar-benar dijalankan; saat ini belum ada klaim bahwa test ML telah berjalan.

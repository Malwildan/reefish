# Batas arsitektur awal

Dokumen ini menetapkan batas organisasi repo, bukan persetujuan atas seluruh rekomendasi teknis. Pilihan layanan, library, skema, dan deployment perlu ditinjau saat kebutuhan implementasi tersedia.

## Domain

- `frontend/mobile/` menampung aplikasi Flutter; UI bukan sumber otoritas aturan backend.
- `frontend/web/` menampung aplikasi Next.js; web menggunakan kontrak yang sama dengan mobile.
- `backend/` menampung migrasi, fungsi, dan pengujian Supabase. Backend memvalidasi akses dan menjadi otoritas data.
- `machine-learning/` menampung eksplorasi dan kode ML dengan tujuan terdefinisi.
- `contracts/` adalah lokasi kanonis kontrak lintas domain. Adapter boleh berbeda, makna kontraknya tidak.

Catatan arsitektur merekomendasikan Supabase sebagai backend awal. Kerangka ini tidak mewajibkan server NestJS terpisah.

## ML dan data

Hasil ML yang membantu ekstraksi atau pengisian data menjadi draf yang dapat diperiksa dan diedit manusia. Jalur input manual tetap tersedia bila model gagal atau hasilnya ditolak. Informasi tanpa metode tervalidasi tetap berstatus `unknown` atau `pending`; jangan membuat klaim lapangan dari output model semata.

Notebook adalah ruang eksplorasi yang terdokumentasi. Jangan commit dataset, data pengguna, bobot model, checkpoint, kredensial, atau keluaran build. Dokumentasikan sumber, izin, dan batas pemakaian sebelum data digunakan.

## Evolusi

Alur pertama yang dituju: nelayan menyimpan trip offline → antrean tersimpan lokal → backend menerima sinkronisasi idempoten → web menampilkan agregat sesuai izin. Backend menerbitkan keputusan kawasan dan versi paket; mobile menampilkan waktu pembaruan serta status sinkronisasi. Data yang belum tersinkron tetap terlihat di perangkat.

Rencana lokasi, lintasan transit, dan lokasi menangkap aktual adalah data terpisah. Gunakan identitas grid berversi yang sama lintas aplikasi; tangkapan campuran tidak dibagi rata ke grid. Aturan final dan fixture lintas bahasa didokumentasikan di `contracts/` saat implementasi.

Mulai dengan kontrak sekecil yang dibutuhkan alur pertama. Perubahan kontrak perlu ditinjau pemilik domain terkait dan mempertimbangkan client lama.

Implementasi awal mobile menyediakan empat layar auth dengan feature-first + Cubit + repository. Bloc untuk lifecycle berlayar ditambahkan ketika fitur tersebut dikerjakan. Backend, sinkronisasi trip, dan aplikasi web belum diimplementasikan pada slice ini; tidak ada klaim deployment production.

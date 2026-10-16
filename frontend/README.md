# Frontend

Reefish memiliki dua aplikasi untuk peran berbeda. Keduanya memakai kontrak Supabase bersama; otorisasi dan aturan data ditegakkan oleh backend.

- [Aplikasi mobile Flutter](mobile/README.md) untuk **nelayan**: akun dan profil, kapal dan perjalanan, data petak laut, cuaca, dan rekomendasi. Go menyediakan endpoint rute yang berstatus simulasi; aplikasi mobile tidak menyajikannya sebagai panduan navigasi operasional yang aman.
- [Aplikasi web Next.js](web/README.md) untuk **konservatif**: memeriksa indikator per grid dan mengelola zona restricted atau rehab.

Supabase RPC memeriksa peran dan aturan data; tampilan aplikasi bukan batas keamanan. README mobile dan web menjelaskan setup, alur demonstrasi, serta batas bukti masing-masing.

README root memuat ringkasan produk, arsitektur, dan bukti implementasi. Folder ini memperlihatkan pembagian peran dan implementasi klien. Dampak operasional memerlukan data sumber yang tervalidasi, pengguna berwenang, dan evaluasi lapangan; belum ada dampak terukur yang diklaim.

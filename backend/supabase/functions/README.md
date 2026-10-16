# Supabase Edge Functions

Fungsi terdaftar dalam source di direktori ini adalah `push-dispatch`. Ia mengambil antrean `push_outbox` lewat RPC internal, mengirim pesan FCM HTTP v1, lalu melaporkan hasil dan percobaan ulang. Fungsi menerima panggilan terjadwal dan memakai secret deployment; jangan simpan kredensial Firebase atau service-role key di source.

Build dan pemeriksaan format/type dijalankan oleh workflow backend dengan Deno. Deploy manual memakai `npx supabase functions deploy push-dispatch` setelah proyek, secrets, dan jadwal disiapkan sesuai [panduan push](../setup/README.md#6-push-notifications-fcm).

Laporan hosted 16 Oktober 2026 mengonfirmasi skema antrean dan fungsi push tersedia, tetapi Firebase, kredensial FCM, scheduler produksi, dan registrasi perangkat mobile belum dikonfigurasi. Karena itu belum ada bukti notifikasi berhasil diterima pengguna.

Autentikasi pengguna tidak memakai Edge Function: aplikasi memanggil Supabase Auth langsung. Verifikasi JWT dan izin data dijalankan oleh Supabase/RLS dan Go API.

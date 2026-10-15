# Backend

Supabase adalah arah rekomendasi awal. Direktori ini menjadi rumah migrasi, fungsi, dan pengujian backend. Kerangka ini tidak mewajibkan server NestJS terpisah.

- `supabase/migrations/` — perubahan skema berurutan.
- `supabase/functions/` — fungsi backend bila diperlukan.
- `supabase/tests/` — pengujian migrasi, akses, dan perilaku backend.

Kontrak kanonis lintas domain berada di `contracts/`. Aturan akses dan validasi ditegakkan di backend, bukan hanya di UI.

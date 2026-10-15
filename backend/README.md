# Backend

Supabase adalah arah rekomendasi awal. Direktori ini menjadi rumah migrasi, fungsi, dan pengujian backend. Kerangka ini tidak mewajibkan server NestJS terpisah.

Supabase menangani auth, data cluster ML, dan zona konservasi. Service Go kecil (`cmd/api`) menghitung rute pergi-pulang dengan estimasi BBM.
Spesifikasi rute: `../docs/spesifikasi-backend-rute-nelayan-golang-gin.md`. Kontrak API: `../contracts/route-api.openapi.yaml`.

Kontrak kanonis lintas domain berada di `contracts/`. Aturan akses dan validasi ditegakkan di backend, bukan hanya di UI.

## Struktur

```
cmd/api/                  wiring: config, adapter -> use case, HTTP server
internal/
  domain/                 aturan murni, tanpa I/O
    physics/              vektor arus/angin, STW-SOG, kurva BBM, cadangan
    routing/              grid 500 m, poligon zona, Dijkstra
    environment/          snapshot kondisi laut (kontrak satuan & arah)
  usecase/planroute/      request, validasi, orkestrasi, hasil; port (interface)
  adapter/
    http/                 Gin: decode JSON, header auth, mapping error -> status
    supabase/             repo grid & zona via PostgREST (JWT user, RLS)
    openmeteo/            provider angin/arus/gelombang
  auth/                   token user lewat context
supabase/
  migrations/             skema, RLS, RPC (berurutan)
  functions/              fungsi backend bila diperlukan
  tests/                  pengujian migrasi, akses, dan perilaku backend
scripts/                  konversi output ML GeoJSON -> CSV untuk import
```

Arah dependency: `adapter -> usecase -> domain`. Domain dan use case tidak mengimpor Gin, HTTP, atau SQL.

## Menjalankan

1. `npx supabase link --project-ref <ref>` lalu `npx supabase db push`.
2. Import data. Output model ML (`clusters_*.geojson` + `metadata.json`) diletakkan di `../machine-learning/data/geojson/`; folder ini diabaikan git.
   ```
   python scripts/geojson_to_csv.py ../machine-learning/data/geojson out
   psql "$SUPABASE_DB_URL" -c "\copy grid_cells(grid_id, geom) from 'out/grid_cells.csv' csv header"
   psql "$SUPABASE_DB_URL" -c "\copy cluster_predictions from 'out/cluster_predictions.csv' csv header"
   ```
3. Jadikan akun konservatif: `update profiles set role = 'konservatif' where id = '<uuid>';`
4. Service rute: export env sesuai `.env.example` (tidak dibaca otomatis), lalu `go run ./cmd/api`.
5. Test: `go test ./...`

## API

| Sumber | Endpoint | Untuk |
|---|---|---|
| Supabase RPC | `get_fishing_spots(p_period, p_min_level)` | Peta spot nelayan; titik di zona `closed` dibuang |
| Supabase RPC | `get_clusters(p_period, p_min_level)` | Peta cluster di dashboard konservatif |
| Supabase REST | `zones` | CRUD zona (tulis hanya konservatif); `geojson` siap dipakai peta |
| Go service | `POST /v1/routes` | Rute + estimasi BBM, header `Authorization: Bearer <JWT Supabase>` |

Detail request/response: `../contracts/route-api.openapi.yaml`.

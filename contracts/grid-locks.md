# Fixed 500 m grid and lock contract

**Owner:** Backend, with mobile and web client review. This contract covers the fixed spatial index used by the fishing log. Cell size, projection, origin, and identifier format are not runtime settings.

## Grid definition

`east-java-pilot` uses one canonical grid: `tp-id-utm49s-500m:v2`. Each cell is a 500 m square in WGS 84 / UTM zone 49S (EPSG:32749), measured from projected origin `(0 m easting, 0 m northing)`. `row` is the northing index and `col` is the easting index. Indices use a sign prefix with no leading zeroes: `p0`, `p1`, `n1`. Cell IDs have the form `tp-id-utm49s-500m:v2:rp{row}:cp{col}`, for example `tp-id-utm49s-500m:v2:rp18134:cp1370`.

The operational area bounds are `[112.25, -9.15, 113.10, -8.35]` in `[west, south, east, north]` order. A cell is within the area only when its projected square has positive-area overlap with those bounds transformed to EPSG:32749. A shared edge alone does not count. The bounds are an operational map boundary, not a legal marine boundary or a claim about fishing suitability.

The persisted trained-data grid is static. The database accepts only 500 m EPSG:32749 definitions with origin `(0,0)` and published or archived state. There is no client RPC to create, preview, or publish a different definition. Grid resolution and cell IDs must not be changed or inferred from zoom level.

## Administrative locks

An area admin is a user listed in the trusted `map_area_admins` relation for `east-java-pilot`. Membership is not derived from caller-editable metadata. No admin membership or active restriction is seeded; an operator must provision admins through a trusted process after verifying the `auth.users` identity.

An admin lock stores the canonical cell ID and a non-empty reason. Every mutation supplies the last observed area version. Mutations serialize on the area row, reject stale versions, increment the version after a real change, and append an audit event. Unlocking removes only the exact active 500 m source cell.

Every future trip/catch write that accepts an actual fishing cell must call `validate_fishing_grid_selection` in the same database transaction as that write. The validator takes a shared lock on the area row while checking the canonical cell geometry and current restrictions. Admin mutations take an exclusive lock on the same row, so an admin change and a fishing write serialize. Planned departure, transit, and actual fishing location are separate values; a departure or transit cell must not be substituted for the actual fishing cell.

The snapshot is authoritative only for administrative restrictions at its returned version and freshness window. A fresh absence means no administrative lock was present in that snapshot. It does not establish legal permission, safety, or suitability. A missing, expired, or failed snapshot is unknown/pending, not permission to select a cell.

## RPCs

All RPCs require a signed-in caller. Snapshot and validator are available to authenticated clients. `set_grid_lock` additionally requires area-admin membership.

| RPC | Parameters | Result |
| --- | --- | --- |
| `get_grid_lock_snapshot` | `p_area_id text` (default `east-java-pilot`) | Exactly `{version, fetched_at, expires_at, is_demo, locks}`. |
| `set_grid_lock` | `p_area_id text`, `p_cell_id text`, `p_locked boolean`, `p_reason text`, `p_expected_version text` | New area version as a decimal string. |
| `validate_fishing_grid_selection` | `p_area_id text`, `p_cell_id text` | `true` only for a canonical in-area 500 m cell with no active lock; otherwise raises an error. |

### Snapshot response

```json
{
  "version": "7",
  "fetched_at": "2026-10-16T04:00:00.000Z",
  "expires_at": "2026-10-16T04:05:00.000Z",
  "is_demo": false,
  "locks": [
    { "cell_id": "tp-id-utm49s-500m:v2:rp18134:cp1370", "reason": "Area review" }
  ]
}
```

Times are UTC ISO-8601 strings. `version` is a decimal string and must be passed back unchanged. The example lock is illustrative only. Each lock has exactly `cell_id` and `reason`.

Expected errors include unauthenticated caller, non-admin caller, unknown area, malformed or non-canonical cell ID, cell outside the area, missing lock reason, and stale version. After a stale-version response, refresh the snapshot before retrying.

## Database boundary

Public tables have RLS enabled and no direct client table grants. Public RPC wrappers are `SECURITY INVOKER` functions with explicit execute grants to `authenticated`. Their private implementations live in `reefish_private`, use a fixed search path, and verify `auth.uid()` and trusted membership where required. Do not add a public admin-grant endpoint.

The forward-only rollback migration is `backend/supabase/migrations/20261016001628_restore_fixed_500m_grid.sql`. It removes the unused 1000 m draft only after checking it has no restriction, audit, or active-area references; it preserves the original 500 m ID and all lock/auth data. Its SQL test is `backend/supabase/tests/fixed_grid.sql`, which uses a synthetic auth user and rolls back its fixtures.

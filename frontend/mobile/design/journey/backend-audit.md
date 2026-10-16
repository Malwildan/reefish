# Create Journey → Dashboard: integration evidence

Verified against Supabase project `upyahsecuorqghcghflg` on 16 October 2026.

- Source contract: `contracts/nelayan-api.openapi.yaml`.
- Journey SQL: `backend/supabase/migrations/20261016100000_schema.sql` through `20261016100500_nelayan.sql`, followed by `20261016100550` deployment compatibility.
- Database schema deployment: the six original migrations were applied in one transaction, followed by a separate compatibility transaction. The three existing fixed-grid migrations were preserved and not replayed.
- Fixed-grid check: the existing grid definitions and locks retained their pre-deployment hash.
- ML grid import: 31,354 point IDs and coordinates imported from the user's GeoJSON, with all 24 source periods matching the import source. Canonical coordinate MD5: `7e3375cc745ccc17d97774c6db43d759`. Import manifest: `backend/supabase/setup/journey-grid-cells.manifest.json`.

The implemented API retains Supabase phone/password authentication. The migration backfilled the one existing Auth account into `profiles` without changing existing roles. No Auth provider settings or credentials were changed.

| Capability | Implemented contract |
| --- | --- |
| Profile / onboarding step | `api_me`, no arguments |
| Initial boat | `api_create_boat`, `{p: BoatInput}` |
| Completed trip | `api_post_trip`, `{p: TripInput}`; stable UUID `client_trip_id` |
| History / summary | `api_list_trips`, named `p_*` filters |
| Trip detail | `api_trip_detail`, `p_id`, optional `p_track` |
| Recommendations / weather | Go `/api/v1/*`, same Supabase user JWT |

The five Journey RPCs are now present and no longer return `PGRST202`. Anonymous requests are denied with HTTP 401 / PostgreSQL `42501`; authenticated calls are owner-checked by the RPCs. Responses are direct JSON objects, except the history object's `data` array. Posting a trip does not generate recommendations.

`backend/supabase/tests/journey_live.sql` passed against the live database using authenticated JWT claims. It covered profile role defaults, boat creation, onboarding trip creation, stable-ID replay, history, detail, direct table-write denial, row-level ownership, and denial of another user's trip detail. Its two fixture accounts and all fixture boats/trips were rolled back. The existing account remains one Auth user and one profile, with zero boats and zero trips; its `api_me` response reports `next_step: boat`.

The deployed SQL prefix stops at Journey and shared route support. After merging `gipar` into `main`, the Go API runs locally with a temporary HTTPS preview tunnel and `REEFISH_API_URL` configured in the ignored local Flutter config. There is no permanent hosted Go deployment yet. Predictions have not been imported, so recommendations remain unavailable; weather uses Open-Meteo independently. The weather-area endpoint authenticates through the already deployed `api_in_pilot` RPC and no longer requires the later heatmap migration. No additional Supabase migration was applied for this weather integration.

The RPC implementation keeps `grid_cells` separate from the fixed 500 m lock definitions. The app sends WGS84 points; the server resolves an ML cell ID. Do not send a `tp-id-utm49s-500m:v2:*` lock ID as an `X*_Y*` ML cell ID.

Security review fixed the seven helper-function search paths and revoked direct execution of Auth trigger functions. The closed `app_config` RLS policy is intentional; `api_mobile_config` is the public configuration endpoint. Authenticated owner-checking `SECURITY DEFINER` RPCs also produce advisor findings. Two pre-existing findings remain outside this deployment: the `rls_auto_enable()` event-trigger function's execute warning and leaked-password protection being off. See Supabase's [SECURITY DEFINER advisor](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) and [leaked-password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

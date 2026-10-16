# Hackathon mobile integration — 16 October 2026

## Running services

- Go API: https://reefish-api-production.up.railway.app/api/v1
- Health: https://reefish-api-production.up.railway.app/health/live
- Supabase project: upyahsecuorqghcghflg
- Configured local Flutter preview: http://127.0.0.1:4195/
- Submission APK: `frontend/mobile/build/app/outputs/flutter-apk/app-release.apk`, version **1.0.0+2**, universal Android release, signed with the dedicated Reefish upload certificate. A copy is at `C:/Users/akmal/Downloads/Reefish-1.0.0-release.apk`. See `frontend/mobile/RELEASE.md` for reproduction and private signing-key backup locations.

Railway runs the existing Go Docker image in the separate `reefish-api` service. It was uploaded from `backend/api` with Railway CLI under the already authenticated Work account and its available trial. No paid subscription was purchased and no GitHub app connection was granted. Source changes are not automatically deployed: upload them again with Railway CLI or configure deployment later.

The ignored `frontend/mobile/config/supabase.local.json` contains the Railway API URL. Build Flutter with `--dart-define-from-file=config/supabase.local.json`; URL/key configuration is compiled into the app. Go expects `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the publishable key value) and `ALLOWED_ORIGIN`. Service-role keys are not used. CORS currently accepts browser origins for the hackathon; authenticated endpoints still require the caller's Supabase JWT.

## Connected mobile features

Authentication, profile, boats and trip/history/detail use existing Supabase repositories. Marine map selection now uses authenticated `api_layers` and `api_habitat`, joins backend source grid IDs onto the canonical fixed 500 m coordinates, preserves missing values as NoData and shows the returned data period. Available period controls follow the server response. When base layer calls are unavailable, the app explicitly identifies its bundled offline snapshot. A failed remote chlorophyll-period call is not silently replaced with older snapshot values.

Grid restrictions follow the current shared contract: cells in active rehab zones remain visible and cannot be selected for fishing. The deployed `rehab_lock` migration mirrors these zones in the existing lock snapshot; `set_grid_lock` is retired in favor of the admin zone RPCs. No real admin account was assigned. See `contracts/grid-locks.md` for the authoritative policy.

Dashboard weather and recommendations call the Railway API with the current JWT. Recommendations are currently labeled heuristic fallback (`heuristic-0.1`); this is not live model inference or a guarantee of catch. Their query was timing out with the imported dataset. The forward performance migration materializes the spatially filtered candidate set before zone lookups, retaining the existing eligibility filters.

## Source data and migrations

All previously pending migrations 20261016100600 through 20261016101100 are deployed, followed by 20261016125501. The zones migration now refuses replacement of a non-empty zones table and preserves the earlier trip idempotency/constraint handling fix. Hosted migration versions were reconciled with their checked-in source filenames.

Imported original data: 31,354 prediction rows for **2025-12**, 31,354 separate `potensi_ikan` rows, 140 coral features and three mangrove features. Only this latest available source month was imported for the demo; the app does not pretend all 24 months are present. These are historical source values, not current observations. Unknown source units and the provisional coral codebook remain explicit. The generator records source hashes and counts in ignored local output; datasets and SQL data batches are not committed.

Use `backend/scripts/prepare_hosted_layers.py --help` to regenerate bounded, idempotent import batches from local source files. Do not run the old `hosted_load.sh` as an incremental loader: its grid-empty condition can skip missing prediction/layer imports when grid cells already exist.

## Verification

- Actual Supabase password authentication for a dedicated temporary probe: HTTP 200.
- Authenticated HTTP profile, boat creation, layer, habitat and lock-snapshot RPCs: HTTP 200.
- Railway authenticated weather: HTTP 200, current forecast present, 2.42 seconds in the recorded probe.
- Railway authenticated forced recommendation refresh: HTTP 200, three items, 3.12 seconds in the recorded probe.
- Journey, zones/quotas and latest-layer SQL integration checks passed. SQL fixtures were rolled back; the temporary HTTP probe was signed out and deleted, including its boat/recommendation records.
- 44 map-related Flutter tests and two import-generator tests passed; `flutter analyze lib tool` passed; Go tests passed.
- Configured Flutter web build passed. Browser render inspection was blocked by the session's browser security policy; no new live UI end-to-end claim is made.
- Configured Android arm64 debug build passed using Microsoft OpenJDK 17 and `--android-project-arg=kotlin.incremental=false` to avoid mixed Windows-drive Kotlin cache failures. `JAVA_HOME` was set only for that build; project Gradle settings were unchanged.
- Submission release build subsequently passed with `lib/main.dart`, the configured Supabase/Railway defines, version 1.0.0+2, and a dedicated release certificate. The APK has `debuggable=false`, a valid v2 signature, INTERNET/location permissions and arm64-v8a/armeabi-v7a/x86_64 libraries. Correct API host strings were verified in all three compiled app libraries. Release signing now requires ignored local signing material; there is no debug-signing fallback.
- SQL syntax check parsed 142 function bodies with zero failures. Two existing files were partly skipped because the parser cannot resolve schema-qualified types.
- All public tables checked have RLS enabled; imported habitat geometries are valid.

The machine-readable boundary checks are in `backend/supabase/setup/integration-verification.json`.

## Remaining scope

This delivery prioritizes the mobile demo. The separate Next.js admin UI (`frontend/web`) now calls the live admin RPCs: heatmap with automatic version updates, ML layers and habitat overlays, zone outlines, zone decisions (create, edit, edit grids, status, history), system flags (list, dismiss) and an asynchronous heatmap refresh (`20261016130000_refresh_async`, not yet on hosted). Violation monitoring is hidden until it has a backend. No konservatif account exists on hosted yet. Its live Supabase integration was verified against the local stack, not as part of this mobile verification. Push database support is installed, but a push sender/FCM credentials and mobile notification registration are not configured. Consent/preferences remain device-local. Recorded GPS works in the foreground and still requires physical-device testing. Offline basemap downloads and offline route calculation are not implemented. The route backend continues to label its output as simulation-only, and the mobile flow does not present it as safe operational navigation.

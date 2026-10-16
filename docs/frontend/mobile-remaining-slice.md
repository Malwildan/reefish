# Remaining mobile slice â€” 16 October 2026

## Implemented scope

Prototype frames are deduplicated into shared screens and session states:

- Journey mode: one screen with unselected, tracked and manual states, following the three user-supplied PNGs.
- Foreground sailing: departure, transit, fishing, stop confirmation, pause/recovery and completed session.
- Account: profile, paginated history, trip detail, initial consent and settings.
- Read-only full map and a shared recommendation detail for fuel/catch variants.
- Existing authentication, onboarding, dashboard, departure/fishing selection and manual form are reused.

## Boundaries and integration

`JourneyEntry` composes repositories, the existing `JourneyCubit`, account preferences and `SailingBloc`. The sailing Cubit owns one serialized lifecycle and persists each state before exposing it. The UI never turns a prototype timeout or stationary GPS point into a fishing event. Departure and actual fishing location require explicit confirmation. The actual point is checked against current grid-lock policy both before and after confirmation.

Available Supabase integrations are reused: `api_me`, `api_list_trips`, `api_trip_detail`, boat operations, `api_post_trip`, configuration and grid policy RPCs. Weather and recommendation detail use the existing Go/Open-Meteo repository. Coordinates, recorded UTC seconds, GPS sequence and `client_trip_id` survive the sailing summary form. Submission retries retain the same payload/ID; the durable session is cleared only after an acknowledged submission. Pending cleanup does not post the trip again. Incomplete recordings offer an explicit manual fallback and retain the original ID.

The account settings store is device-local and account-scoped. Location access requires both the app preference and the operating-system permission. Backgrounding pauses foreground recording. Restoring a session does not silently restart GPS. A paused or stale GPS fix is not labeled as current. Account changes discard the old visible flow and stop its recording.

Missing backend capabilities stay explicit: region sharing is disabled, consent is not represented as server-synced, unavailable financial fields remain unknown, and no push/inbox backend is claimed. Trip-detail status reflects the successful account read rather than the source mockup's pending-sync placeholder. No production schema or account data was changed for this slice.

## Map and tracking limits

The existing canonical EPSG:32749 grid stays fixed at 500 Ã— 500 m. OpenStreetMap is the online basemap; visible attribution is retained above covering sheets. Recommendations and recorded tracks are not presented as safe navigation routes. This change does not implement offline basemap downloads or background GPS. A route-service prototype does not establish navigational safety near shore.

Sailing uses qualified foreground GPS (finite in-range coordinates, bounded accuracy, freshness and monotonic timestamps), a 5,000-point recording cap, serialized durable writes and generation guards against callbacks arriving after pause/finish. Its small session store currently uses SharedPreferences; a larger offline outbox/history system should use the planned transactional SQLite/Drift implementation rather than expanding this store indefinitely.

## Verification

See `frontend/mobile/design-qa.md` and `frontend/mobile/qa/remaining/README.md` for reference images, browser comparisons, fixture boundaries and commands. Synthetic QA values and explicitly emitted synthetic GPS samples never enter production Supabase.

Native GPS accuracy, lifecycle behavior on physical Android/iOS devices, background tracking and real-account end-to-end writes have not been verified by the browser fixture.

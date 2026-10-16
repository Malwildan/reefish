# Remaining mobile UI: design QA

Reviewed 16 October 2026 against the three user-supplied mode images and current canonical Figma exports in `design/remaining/`. Prototype duplicates are shared screen states. `source-manifest.json` records hashes and verified frame IDs; permission IDs remain unconfirmed.

## Result

The agreed screens and backend composition are implemented. Browser verification covers mode selection, initial consent/settings, profile/history/detail, recommendation variants, full map, departure/transit/fishing, stop/cancel and paused recovery. Captures were inspected at 430 Ã— 932 and six representative screens at 360 Ã— 640. No overflow or runtime console errors were observed in the inspected flows. Recorded completion opens the form with exact original seconds and location, rather than editable rounded times.

Fifteen `qa/remaining/compare-*.jpg` images show source left and Flutter right. Twenty-two PNG captures include paused state and narrow layouts. Final settings, fishing and stop-dialog captures were refreshed after the last spacing changes, and their affected tests passed. Narrow captures remain representative responsive evidence rather than pixel-exact goldens.

## Repairs made during comparison

- Replaced the old photographic mode cards with the supplied white-sheet/radio design.
- Restored bottom navigation on account, detail and recommendation pages and reused one navigation widget.
- Aligned sheet/header positions, cards, CTA spacing, switches and initial-consent branding.
- Moved recommendation metadata below the principal map/cards.
- Preserved OSM attribution when a sheet covers the map; improved compass contrast.
- Qualified current GPS markers by status/freshness and enabled following the recorded current position.
- Kept the session panel background through the native bottom safe area.

## Deliberate differences from reference content

OSM replaces the satellite-like design basemap as requested. The app does not draw a fictional route or hotspot. Values come from the backend or explicitly synthetic QA fixtures; unknown financial values remain `â€”`. The backend summary does not return a port label. A successful account read says saved rather than copying the mockup's pending-sync state. Initial consent is recorded locally and regional sharing remains disabled because its backend is unavailable. Departure/fishing require explicit confirmation; prototype timers and automatic-detection copy are not implemented as GPS logic. The stop dialog reports actual elapsed time instead of a fabricated countdown. Native OS status-bar/home-indicator chrome is outside application fidelity scope.

## Validation and limits

- 195 selected tests passed; the independently modified `session_restore_test.dart` was excluded after hanging during the full run.
- Subsequent affected sailing/integration/dashboard tests passed (12), followed by permission/sailing tests (8) after the last small UI changes.
- `flutter analyze lib tool` passed.
- The synthetic QA web build and configured application preview build passed; the preview serves on localhost:4195.
- Native physical-device GPS, background recording, offline tile downloads and real-account end-to-end writes were not validated by this fixture. This slice implements foreground tracking only.

No production backend schema or user data was mutated for these fixtures. Unrelated concurrent authentication/session-storage changes were preserved.

## Follow-up: idle contrast and repeat QA start

The reported idle panel used white text on a light background. White text now applies only to departure/transit dark panels; idle title/body/error use dark colors. Repeated QA Start resets only its synthetic in-memory store and guards overlapping starts. Browser verification confirmed departure after repeated Start with no prior-session error. All five sailing UI tests, targeted Dart analysis and both web builds passed.

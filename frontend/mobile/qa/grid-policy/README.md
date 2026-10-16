# Grid policy recovery verification — 16 October 2026

The reported five-cell failure was caused by the preview process being started without Supabase dart-defines. `UnconfiguredGridPolicyRepository` could never load policy; the Cubit discarded the cause and suggested choosing another cell or reloading. Restarting with `config/supabase.local.json` enables the real backend. The normal snapshot RPC also requires authentication, so direct map preview access while signed out needs a login action.

The fix distinguishes missing configuration, missing session, denied permission, unavailable service, and invalid responses. Signed-out users can open the existing login screen. Unknown policy stays blocked for fishing selections, including when an earlier cached snapshot marked a cell open. Known locks remain blocked. No backend grants or policy data were changed.

Regression evidence:

- Before the fix, `grid_policy_unconfigured_regression_test.dart` failed against the real unconfigured repository with the exact reported generic message. After the fix, all five distinct cell selections and refreshes identify missing configuration.
- Repository tests use mock HTTP with the real Supabase client to check successful parsing and each recovery category. These are not live authenticated tests.
- Cubit tests cover a lost session after a cached-open snapshot, five distinct cell selections remaining blocked, and recovery after successful refresh.
- Widget tests verify the sign-in action instead of a misleading reload action.
- `flutter test --no-pub --reporter expanded`: all 90 tests passed.
- `flutter analyze --no-pub`: no issues found.
- `flutter build web --no-pub -t tool/preview.dart --dart-define-from-file=config/supabase.local.json --no-web-resources-cdn`: succeeded. Flutter emitted a font-family warning about CupertinoIcons; the verified login action uses the existing Material/asset icons.
- A read-only anonymous call to the live snapshot RPC returned HTTP 401 / PostgreSQL code 42501, confirming the authentication requirement. The live Auth settings endpoint returned HTTP 200. No account was created, no SMS was sent, and no real account login was attempted.

Browser evidence is recorded separately in `configured-auth-qa.json` and screenshots. Browser taps may resolve to the same cell through Flutter semantics; the JSON records distinctness explicitly, while the Cubit regressions cover distinct cells.

The configured guest browser displayed the exact authentication-required message and opened the existing phone/password login form. No page or console errors were recorded. At 360 × 640 the screenshot is visually contained, but the DOM scroll-width check reported 388 px; this browser report therefore retains a failing overall flag pending overflow diagnosis. An authenticated live fishing save was not tested.

# Selected-cell data performance — 16 October 2026

The compact popup used to request the full 24-entry chlorophyll timeline even though it displayed only one entry. With the repository's two-entry LRU, selecting a different uncached cell read and decoded all 24 CSVs again. This was the dominant measured cost.

The summary now requests only its selected export-order entry. That entry is warmed after the base map dataset becomes ready, without delaying base readiness, and shared across cells and concurrent requests. The selected entry is retained alongside at most one other entry in the Cubit; the asset repository retains its existing two-entry LRU. The full 24-entry timeline is still available through Detail data and is loaded on demand. Failed preload attempts do not become cached empty results, and explicit loads can retry.

Coral/mangrove polygon bounds are prepared once per immutable dataset. Exact cell intersections use a 128-cell LRU, while original polygon rings/holes and boundary semantics remain intact. Render coordinates and styled area layers are reused rather than reconstructed for each selection. These caches contain source data only: admin policy freshness, known locks, authentication, and save-time validation remain live checks.

## Measured results

Run: `flutter test --no-pub test/marine_selection_benchmark_test.dart --reporter expanded`.

The benchmark uses real bundled assets through Flutter's native VM test harness and native file reads. It measures data/domain work, not browser frame rate or physical-phone tap latency. Timings vary by machine load; CSV read counts provide a stable regression signal.

| Measurement | Before | After |
| --- | --- | --- |
| First selected-cell chlorophyll request | 2,473 ms | 157–268 ms in two dedicated runs; 282 ms during the full suite |
| Next distinct cell | 2,546 ms | below 1 ms at recorded millisecond precision, no asset read |
| Chlorophyll asset reads | 48 reads for two distinct cells | 1 read for five distinct cells plus a repeat |
| Source bytes per cold summary entry | all 24 files, 27,437,084 bytes | one file, 1,143,150 bytes |

`baseline.json` preserves the original run. `after.json` retains both dedicated after runs, including base initialization. Geometry timings use different cache strategies and are recorded as supporting diagnostics, not a device speedup claim. The benchmark does not overwrite these evidence files during regular tests.

Validation: the current workspace suite passed all 134 tests; `flutter analyze --no-pub` found no issues. Tests cover five-cell reuse, same-entry concurrent loads, nonblocking preload, retry after failed preload, entry changes, lazy full-detail loading, bounded concurrency, source-value correctness, geometry holes/boundaries, cache eviction, and dataset scoping.

The configured in-app browser was also checked through a new grid selection: all six categories, the selected chlorophyll value, and the policy badge rendered correctly (`browser-summary.png`). This is a functional smoke check, not a measured end-to-end UI latency benchmark. No credentials were entered and no point was saved during this check.

The configured preview web build succeeded. Flutter emitted the existing CupertinoIcons font-family warning; no new build error was reported. Android/iOS device performance remains unmeasured.

The caches live for the current map instance. They are not persistent offline tile/data downloads, and do not guarantee retention after closing the map or restarting the app. No backend data or grants changed.

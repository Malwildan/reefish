# Map popup and coverage boundary — 16 October 2026

Tapped cells now open an in-map white popup instead of a modal bottom sheet. The card keeps the complete six-category parameter summary, source records, grid identity, lock status, and expandable 24-entry chlorophyll data. Content scrolls within the space above the existing departure/fishing flow panel. Closing the popup leaves the selected point intact. Selecting another cell replaces its metadata, with cell-keyed state preventing an older asynchronous result from appearing on the new cell.

The popup has no route or modal barrier, allowing map gestures in the exposed map area. The map's dim overlay is below the popup so the card stays white. The layer configuration sheet is unchanged.

When the viewport exceeds the 600-cell rendering cap, a teal `[6,5]` dashed rectangle shows the configured grid extent. It follows the grid visibility setting. This is an application coverage window, not a legal or administrative boundary; it does not change the canonical 500 m grid, data coverage, or access policy.

Validation:

- All 93 Flutter tests passed, including popup scrolling at 328 × 200 with text scale 1.3, close callbacks without route pops, stale-response handling, and existing lock/authentication behavior.
- After moving the dim overlay below the popup, the 6 relevant popup, departure, and sign-in widget tests passed again.
- `flutter analyze --no-pub`: no issues found.
- After reserving space for the OSM attribution, the 5 popup/departure widget tests passed again.
- The final configured preview web build succeeded. Flutter still emitted the existing CupertinoIcons font-family warning.
- Browser screenshots confirm the white popup at 430 × 932 and 360 × 640, and the dashed grid extent at low zoom. The first 360 px check found all six parameter categories before and after a short scroll, a close button, and no page errors; the primary agent inspected that passing output and screenshot. The later deeper-scroll probe overwrote `popup-360-qa.json` with `pass: false` because the summary labels were no longer in the DOM while viewing chlorophyll details. This metric cannot establish that those categories are inaccessible: the ListView lazily removes offscreen children. Both observations are retained in `map-popup-qa-summary.json`. The visible layout fits; Flutter's semantics DOM reports a wider scroll width with `windowScrollX: 0`, as in the earlier map preview.
- The broader browser harness stopped on its second-cell interaction setup and did not verify replacement, gesture persistence, or grid-toggle behavior. Do not treat those checks as passed. Cell replacement is implemented with cell-keyed widget state; stale-result behavior is covered by the widget tests.
- Browser checks use a signed-out preview and do not verify a live authenticated fishing save.

Native Android/iOS behavior has not been tested in this change.

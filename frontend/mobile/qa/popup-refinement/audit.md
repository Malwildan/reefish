# Grid popup refinement — 16 October 2026

Scope: improve the existing Flutter grid popup within Reefish's current map and departure/fishing flow. The current product, blue/peach palette, DM Sans typography, data semantics, and grid access checks remain the reference.

## Current-run evidence

1. Initial departure screen (`01-before.png`): the blue flow panel occupies much of the available vertical space. Map controls and attribution are visible. This is the tutorial/selection state, not a metadata inspector.
2. Tapped grid (`02-popup-before.png`): the nearly full-width white popup competes with the blue flow panel. A long canonical grid ID occupies the subtitle, and the parameter table extends beyond the visible card. The most useful values do not form a clear scanning hierarchy. The source/missing-data explanations require substantial scrolling.

These screenshots were captured from the current in-app browser and inspected in this run. They show the current desktop browser's centered mobile canvas; they are not native Android/iOS captures. Visual inspection alone does not establish full accessibility compliance.

## Scoped changes

- Use a smaller summary card with a readable row/column label, six parameter values arranged in two columns, and a concise access badge.
- Keep source units and observation time explicitly unknown; preserve record counts as source records, not habitat coverage or absence claims.
- Offer a separate centered `Detail data` dialog containing the existing full metadata and all chlorophyll entries.
- Reduce the redundant flow panel to its relevant selection/action controls while the popup is open, retaining the real login/refresh/save rules.
- Keep close and detail actions reachable, allow scrolling at enlarged text sizes, and prevent attribution or map controls from obscuring the card.

The request is a scoped edit of the existing product, so the current screen and design system are the visual target. No new app scaffold, hosting, generated visual direction, or deployment is involved.

## Verification after refinement

1. Grid summary — verified in the in-app browser (`03-after-summary.png`). All six metrics and the unknown-unit/time caption are visible, with shorter grid identity, a compact policy badge, and reachable detail/close controls. The layer control is hidden while the card is open instead of peeking from behind it. The lower action panel is compact.
2. Full metadata — verified (`04-after-details.png`). `Detail data` opens a centered scrolling dialog. Closing the dialog returns to the same summary and cell identity, without a drawer or navigation away from the map.
3. Summary close — verified through the current accessibility tree. The popup disappears, the normal departure panel and layer control return, and Save remains available. No record was saved or authenticated login attempted during this visual verification.

The before and after screenshots use the same browser viewport and map-selection flow but different selected cells. They compare layout, not equality of source values. The primary agent inspected both local screenshots; the browser canvas is 430 px wide within the desktop preview. No native-device capture or claim of full accessibility compliance is made.

The complete suite passed 99 tests; the six summary/preview tests passed again after final spacing edits. `flutter analyze --no-pub` found no issues. The preview-canvas test first reproduced the desktop MediaQuery size mismatch, then passed after its size was bound to the actual mobile canvas. Narrow-card tests cover 288 × 250 with text scale 1.3, error retry, missing values, callback behavior, and stale asynchronous results.

# Remaining-screen visual QA

`tool/remaining_preview.dart` renders the production widgets with a synthetic, in-memory repository, fake permissions and a controlled GPS stream. It does not configure Supabase or bypass production authentication. The right-hand control panel is outside the captured app boundary. Map tiles are live OpenStreetMap context, not synthetic predictions.

## Run

From `frontend/mobile`:

```powershell
flutter build web -t tool/remaining_preview.dart --output build/remaining-qa --no-web-resources-cdn --no-wasm-dry-run
python qa/remaining/serve.py
```

Open `http://127.0.0.1:4197/` (430 × 932) or `http://127.0.0.1:4197/?width=360&height=640`. Enable Flutter accessibility if using semantic browser controls. Scroll the QA panel to reach lower controls, and scroll it back to reach the capture button. Check the visible phase after each action; a click attempt alone is not evidence.

The capture button saves exactly the app viewport (including its Navigator/dialog overlays) through the loopback-only server. The handler accepts bounded PNG payloads and fixed filenames only. No external upload occurs. `remaining-*.png` are Flutter captures; `compare-*.jpg` show source left and Flutter right. Native status-bar/home-indicator chrome in the source is excluded from app-owned fidelity requirements.

Source images and a hashed manifest are in `../../design/remaining/`. The three mode images come from the ZIP supplied by the user. Current canonical Figma exports take precedence over historical frame IDs. Permission IDs remain unverified and are not guessed.

## Functional fixtures

Start a tracked QA session, emit a sample, confirm departure, emit another sample and explicitly confirm fishing. Stop/cancel, pause/resume and completion are production UI/state operations with synthetic GPS. The resulting summary keeps recorded times and coordinates. Any submission accepts only an in-memory fake ACK; it proves component behavior rather than a production database write.

## Automated validation

The selected suite excludes `test/session_restore_test.dart`, a separately modified authentication test that hung during the first full run. All other selected tests passed (195). After subsequent visual-only changes, affected sailing, integration and dashboard tests were rerun. `flutter analyze lib tool` is clean. See the design report for the final build/capture result.

# Session persistence browser QA

`check-session.cjs` exercises Flutter web authentication persistence in headless Edge. It uses a synthetic account/session and intercepts every Supabase HTTP request. The password and refresh grants are fixture responses; the local public config is read only for `SUPABASE_URL`, and the publishable key is never read, printed, or included in the report.

The scenarios cover signing in through the actual login form, same-origin reload restoring the signed-in route without another password grant, restoring an expired persisted session through a refresh grant, a transient refresh network failure, and explicit logout followed by reload. The script checks that refreshed storage has a future expiry, that logout removes the browser session, and that reload does not issue another password grant. Flutter web's rendered text semantics become unavailable after some route replacements in this preview, so screenshots preserve the visible dashboard, profile, outage, and post-logout states for visual review. Unexpected Supabase endpoints are blocked and cause the run to fail. Other external requests, including map tiles and Go service calls, are blocked before network access. No live account or backend records are changed.

Run with the rebuilt Flutter web preview already listening at port 4195:

```powershell
$env:NODE_PATH = 'C:\Users\akmal\OneDrive\Documents\ChatGPT\joints\_analysis_runtime\node_modules'
$env:PREVIEW_URL = 'http://127.0.0.1:4195'
node frontend/mobile/qa/session/check-session.cjs
```

The script writes `verification.json` and screenshots next to itself. The report includes grant counts, storage outcome booleans, and blocked external request counts; it never includes session values or the publishable key. This test proves browser `localStorage` persistence for the tested web origin and browser context. It does not prove native Android or iOS storage protection or persistence; those require the platform-specific adapter tests and device verification.

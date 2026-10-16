# Weather dashboard QA

`check-weather.cjs` runs the Flutter preview in headless Edge at the dashboard route and checks the Go API URL compiled into that build. Set `GO_API_URL` to that exact base, ending in `/api/v1`; mismatched weather or recommendation requests are blocked locally and fail the run. The Supabase URL is read from `config/supabase.local.json`, but its public key is never printed or copied into the report.

The browser run uses local fixtures for Supabase auth, profile, and trip history and intercepts only Go `weather` and `recommendations` responses. It checks the home-port coordinates, displayed temperature and converted wind speed, wave height, Open-Meteo and DWD attribution, a null marine value, a weather 503 with no stale numbers, and the scrolled 360x640 view. Recommendations return a fixture 503 to exercise independent weather rendering. Unknown Supabase calls and other Go endpoints are blocked. No production auth, boat, trip, or recommendation writes occur.

Run it with Node.js, Playwright available through `NODE_PATH`, and the matching Flutter preview already serving:

```powershell
$env:NODE_PATH = 'C:\path\to\node_modules'
$env:PREVIEW_URL = 'http://127.0.0.1:4195'
$env:GO_API_URL = 'https://your-api-host/api/v1'
node frontend/mobile/qa/weather/check-weather.cjs
```

The run writes `verification.json` and screenshots beside the script. In the 360x640 screenshot, the page is scrolled so the full weather strip and both attribution links sit above the fixed navigation. The map in these captures is incidental; this suite does not verify basemap tiles or map rendering.

## Live backend evidence boundary

The browser suite does not authenticate against the live Go API: it intercepts those browser requests to keep the UI cases deterministic. Separate live smoke checks in this integration verified API health returned HTTP 200, anonymous or invalid-JWT weather requests returned HTTP 401, and a weather CORS preflight from the preview origin returned HTTP 204. The Open-Meteo provider was also exercised directly for the fixture home port (-8.433, 112.683) and returned finite temperature and wind values for the checked hours; wave data was available in both hours during that check. This is provider-level evidence, not an authenticated Flutter-to-Go browser run. The browser fixture verifies the null-wave UI behavior independently.

To launch the Go API from PowerShell using the local public Supabase settings, use `backend/scripts/run-api.ps1`:

```powershell
.\backend\scripts\run-api.ps1 -GoPath 'C:\path\to\go.exe' -Port 8080 -AllowedOrigin 'http://127.0.0.1:4195'
```

The helper reads `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from `frontend/mobile/config/supabase.local.json`, maps the key to the Go process's `SUPABASE_ANON_KEY`, and restores the shell environment when Go exits. It does not print the key or modify the public config.

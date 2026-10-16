# Go route service (`nelayan-route`)

Computation that does not fit Postgres: route + fuel (`POST /v1/routes`), recommendations (`GET /api/v1/recommendations`), and weather (`GET /api/v1/weather`, `/api/v1/weather/area`). Every call needs `Authorization: Bearer <Supabase access token>`; the service calls Supabase with that token, so RLS and the `api_*` role checks still apply. Mobile clients use the service base URL ending in `/api/v1` and pass the current Supabase access token on each request.

Point weather accepts `lat`, `lng`, and optional `hours` (default 24; range 1–48). Its response contains the current UTC hour, the following hourly forecast, and `fetched_at`. Open-Meteo marine values can be unavailable near shore; those fields remain `null` and risk is `unknown` when wind or waves are missing. Weather answers are cached in memory for 30 minutes per ~1 km cell (`internal/adapter/openmeteo/cache.go`).

## Local

```sh
export SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=<anon key from `npx supabase status`>
export ALLOWED_ORIGIN=http://localhost:3000  # exact web origin when calling from a browser
go run ./cmd/api          # :8080, health at /health/live
go test ./...
```

When running under PowerShell, set the same values with `$env:SUPABASE_URL`, `$env:SUPABASE_ANON_KEY`, and `$env:ALLOWED_ORIGIN`. Keep the origin exact for browser clients; native Flutter requests do not use browser CORS.

## Docker

```sh
docker build -t reefish-api .
docker run -p 8080:8080 -e SUPABASE_URL=http://host.docker.internal:54321 -e SUPABASE_ANON_KEY=... reefish-api
```

## Deploy to Render (current, free)

`render.yaml` at the repo root is a Render Blueprint for this service (Docker, free plan, Singapore, branch `gipar`, redeploys only when `backend/api/**` changes).
1. render.com → sign in with GitHub → New → Blueprint → pick `Malwildan/reefish`, branch `gipar`.
2. Fill `SUPABASE_ANON_KEY` with the anon (or `sb_publishable_…`) key. Leave `ALLOWED_ORIGIN` empty until the admin web has a URL.
3. Apply. When the build is done, `curl https://reefish-api.onrender.com/health/live` returns 200 (the URL is shown in the dashboard).

The free plan sleeps after ~15 minutes idle; open `/health/live` before a demo to wake it.

## Deploy to Cloud Run (needs a billing account)

**Status: pending (Google Cloud SDK not set up yet).** One-time setup:

```sh
gcloud auth login
gcloud config set project <project-id>          # billing must be on
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```

Deploy from `backend/api` (Cloud Build builds the `Dockerfile`):

```sh
gcloud run deploy reefish-api --source . --region asia-southeast2 --allow-unauthenticated \
  --set-env-vars SUPABASE_URL=https://upyahsecuorqghcghflg.supabase.co,SUPABASE_ANON_KEY=<anon key>,ALLOWED_ORIGIN=<exact web origin>
```

- `--allow-unauthenticated` only opens the network path; each request still needs a valid Supabase token.
- The anon key is public, but keep it in the env var, not in git.
- Check: `curl https://<service-url>/health/live` returns 200, then call `/api/v1/weather?lat=-8.43&lng=112.68` with a token from a demo login.
- Give the service URL to the Flutter and Next.js apps as the Go base URL.

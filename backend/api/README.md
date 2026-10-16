# Go route service (`nelayan-route`)

Computation that does not fit Postgres: route + fuel (`POST /v1/routes`), recommendations (`GET /api/v1/recommendations`), and weather (`GET /api/v1/weather`, `/api/v1/weather/area`). Every call needs `Authorization: Bearer <Supabase access token>`; the service calls Supabase with that token, so RLS and the `api_*` role checks still apply.

Open-Meteo answers are cached in memory for 30 minutes per ~1 km cell (`internal/adapter/openmeteo/cache.go`).

## Local

```sh
export SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=<anon key from `npx supabase status`>
go run ./cmd/api          # :8080, health at /health/live
go test ./...
```

## Docker

```sh
docker build -t reefish-api .
docker run -p 8080:8080 -e SUPABASE_URL=http://host.docker.internal:54321 -e SUPABASE_ANON_KEY=... reefish-api
```

## Deploy to Cloud Run

**Status: pending (Google Cloud SDK not set up yet).** One-time setup:

```sh
gcloud auth login
gcloud config set project <project-id>          # billing must be on
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```

Deploy from `backend/api` (Cloud Build builds the `Dockerfile`):

```sh
gcloud run deploy reefish-api --source . --region asia-southeast2 --allow-unauthenticated \
  --set-env-vars SUPABASE_URL=https://upyahsecuorqghcghflg.supabase.co,SUPABASE_ANON_KEY=<anon key>,ALLOWED_ORIGIN=<admin web origin>
```

- `--allow-unauthenticated` only opens the network path; each request still needs a valid Supabase token.
- The anon key is public, but keep it in the env var, not in git.
- Check: `curl https://<service-url>/health/live` returns 200, then call `/api/v1/weather?lat=-8.43&lng=112.68` with a token from a demo login.
- Give the service URL to the Flutter and Next.js apps as the Go base URL.

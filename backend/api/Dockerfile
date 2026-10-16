# Cloud Run image for the Go route service. Build from this directory:
#   docker build -t reefish-api .   (or: gcloud run deploy reefish-api --source .)
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /api /api
# Cloud Run sets PORT; main.go falls back to 8080.
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/api"]

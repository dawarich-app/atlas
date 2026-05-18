# syntax=docker/dockerfile:1.7

# ---------- Build stage ----------
FROM golang:1.22-alpine AS build

WORKDIR /src

# Cache module downloads
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build a static binary
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ENV CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH}
RUN go build -trimpath -ldflags="-s -w" -o /out/apo-control ./

# ---------- Runtime stage ----------
FROM alpine:3.20

RUN apk add --no-cache \
    ca-certificates \
    curl \
    docker-cli \
    docker-cli-compose \
  && update-ca-certificates

WORKDIR /app

COPY --from=build /out/apo-control /usr/local/bin/apo-control

ENV LISTEN_ADDR=":8090" \
    COMPOSE_PROJECT="atlas" \
    COMPOSE_FILE="/work/compose.yml" \
    STATE_DIR="/var/lib/apo-control" \
    DATA_DIR="/work/data" \
    REGIONS_DIR="/work/regions"

EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:8090/healthz" || exit 1

ENTRYPOINT ["/usr/local/bin/apo-control"]

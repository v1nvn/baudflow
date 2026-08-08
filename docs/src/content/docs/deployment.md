---
title: Deployment
description: "Run baudflow in production: Docker, Docker Compose, and Kubernetes manifests, environment, health, metrics, backups, and security."
section: Start
order: 15
updated: '2026-08-08'
---

## Container image

A multi-arch image (`linux/amd64`, `linux/arm64`) is built for every release tag
and published to the GitHub Container Registry:

```
ghcr.io/v1nvn/baudflow:%VERSION%
```

It is a two-stage Elixir release: a self-contained BEAM bundle that runs as
**non-root UID 1000**, with the Ookla CLI pre-installed at
`/usr/local/bin/speedtest`. Pin a `:%VERSION%`-style tag for stability; `:latest`
follows `main`.

## Requirements

- **Postgres** — any reachable 14+ instance. baudflow owns its schema;
  migrations run automatically on boot.
- **A secret** — `SECRET_KEY_BASE`, 64+ bytes. Generate with
  `openssl rand -base64 48`.
- **A host + port** — the container listens on `4000`; put a reverse proxy in
  front.

No config file, no volume mount, no `CAP_NET_RAW`. Everything else is an env
var.

## Docker

Bring your own Postgres and point the container at it. The image migrates on
boot, so a single `docker run` against a fresh database comes up ready:

```sh
SECRET_KEY_BASE=$(openssl rand -base64 48)

docker run -d --name baudflow -p 4000:4000 \
  -e DATABASE_URL="ecto://postgres:postgres@host.docker.internal/baudflow" \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e PHX_HOST="baudflow.example.com" \
  ghcr.io/v1nvn/baudflow:%VERSION%

# open http://localhost:4000
```

Migrations run on every boot. You can also run `/app/bin/migrate` manually at
any time.

## Docker Compose

baudflow and Postgres in one file, with a healthcheck gating startup:

```yaml
# docker-compose.yml  -  baudflow + postgres in one command
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: baudflow
      POSTGRES_PASSWORD: change-me
      POSTGRES_DB: baudflow
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U baudflow"]
      interval: 5s
      retries: 5

  app:
    image: ghcr.io/v1nvn/baudflow:%VERSION%
    restart: unless-stopped
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: "ecto://baudflow:change-me@db/baudflow"
      SECRET_KEY_BASE: "${SECRET_KEY_BASE}"   # set in a .env file
      PHX_HOST: "baudflow.example.com"
      PHX_SERVER: "true"
    depends_on:
      db: { condition: service_healthy }
    # The image migrates on boot, so no entrypoint override is needed.

volumes:
  pgdata:
```

Put the secret in a sibling `.env` so it never touches the compose file:

```sh
# .env  (gitignored)
SECRET_KEY_BASE=replace-with-openssl-rand-base64-48
```

```sh
$ docker compose up -d
```

## Kubernetes

A single manifest: Namespace, Deployment, Service, Ingress. Uses
a portable `networking.k8s.io/v1` Ingress so it works under Traefik, nginx-ingress,
or Caddy unchanged.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: baudflow
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: baudflow
  namespace: baudflow
spec:
  replicas: 1
  strategy:
    type: Recreate          # single replica; avoid two app pods fighting over schedules
  selector:
    matchLabels:
      app: baudflow
  template:
    metadata:
      labels:
        app: baudflow
    spec:
      securityContext:       # the image needs no special capabilities
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: baudflow
          image: ghcr.io/v1nvn/baudflow:%VERSION%
          ports:
            - containerPort: 4000
              name: web
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef: { name: baudflow-db, key: uri }
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef: { name: baudflow-secrets, key: secret-key-base }
            - name: PHX_HOST
              value: baudflow.example.com
            - name: PHX_SERVER
              value: "true"
          livenessProbe:
            httpGet: { path: /health, port: web }
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet: { path: /health, port: web }
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits: { memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: baudflow
  namespace: baudflow
spec:
  selector: { app: baudflow }
  ports:
    - port: 4000
      targetPort: web
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: baudflow
  namespace: baudflow
spec:
  rules:
    - host: baudflow.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: baudflow, port: { number: 4000 } }
```

Bring the secrets and apply:

```sh
kubectl create secret generic baudflow-secrets \
  --from-literal=secret-key-base="$(openssl rand -base64 48)"

# baudflow-db holds the connection string to your postgres
kubectl create secret generic baudflow-db \
  --from-literal=uri="ecto://baudflow:change-me@my-postgres.baudflow.svc:5432/baudflow"

kubectl apply -f baudflow.yaml
kubectl -n baudflow rollout status deploy/baudflow
```

The container migrates on boot before serving, so no init container is needed.

The `/health` probe is already wired for liveness and readiness. TLS termination
lives in your Ingress; set `PHX_HOST` to the public hostname and let the proxy
hold the certificate.

## Environment

Only `DATABASE_URL` and `SECRET_KEY_BASE` are required for a production release;
see [Environment variables](../environment-variables/) for the full list,
including `PHX_HOST`, `PORT`, `POOL_SIZE`, and clustering options. Notification
transport wiring (for example the ntfy endpoint) is set through application env,
not these process env vars — see [Notifications](../notifications/).

## Why PostgreSQL?

baudflow leans on Postgres for the workload it is good at: typed columns, JSON
storage for the full raw result of every test, and window queries for baselines
and SLA. The container ships with everything else; you just provide the
database. There is no SQLite or MySQL mode, and none is planned — the schema
uses those features deliberately.

## Health & monitoring

- **`GET /health`**: returns `{"status":"ok"}`. Point an external uptime monitor
  (Uptime Kuma, a Kubernetes liveness probe) here.
- **`GET /metrics`**: Prometheus text format, hand-rolled with no cache and no
  dependencies. Scrape it for the `baudflow_*` gauges. See
  [Prometheus](../prometheus-metrics/) for the full list.

Both endpoints bypass the browser pipeline deliberately: `/metrics` serves plain
text so scrapers avoid JSON content-negotiation and the CSRF/session plugs.

## Backup & restore

The Postgres database is the only state. The app container carries no volume and
no local cache — stop, remove, and replace it freely. Every measurement row
stores the full raw Ookla JSON in `raw_result` alongside the ping fields
(latency, jitter, low, high, packet loss), so a database dump is a complete
record.

Back up:

```sh
pg_dump --no-owner --no-privileges -Fc -d baudflow -f baudflow-$(date +%F).dump
```

Restore into a fresh database (`-1` runs the restore in one transaction so a
failure rolls the whole thing back):

```sh
pg_restore --no-owner --no-privileges -1 -d baudflow baudflow-YYYY-MM-DD.dump
```

Point the container at the restored database and it resumes from the last stored
measurement. The `CleanupWorker` prunes rows older than `retention_days` (default
365) daily at 03:00 — schedule backups at least that often if you want pruned
history kept outside the live database.

## Security & access

baudflow is single-user by default and assumes it sits behind your own reverse
proxy or auth proxy (the project itself runs behind one). There is no built-in
login yet; the default is intentionally frictionless for a homelab. Auth is on
the roadmap. Until then, put an auth proxy in front and expose `/health` and
`/metrics` only if you intend to scrape them from outside the boundary.

## Reverse proxy & TLS

The container serves plain HTTP on `:4000`. It has no built-in TLS and no
built-in login — terminate TLS at a reverse proxy and forward to `:4000`. Set
`PHX_HOST` to the public hostname; baudflow uses it to build URLs and to gate the
WebSocket origin.

baudflow is a Phoenix LiveView app, so the proxy must forward the WebSocket
upgrade headers (`Connection: Upgrade`, `Upgrade: websocket`). A proxy that
strips them lets the page load and then silently drops the live connection.
Caddy and Traefik forward these by default; a hand-rolled nginx config that does
not is the usual breakage.

Caddy (`Caddyfile`):

```caddy
baudflow.example.com {
    reverse_proxy baudflow:4000
}
```

Caddy obtains and renews the certificate on its own.

Traefik (compose labels on the `app` service):

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.baudflow.rule=Host(`baudflow.example.com`)"
  - "traefik.http.routers.baudflow.entrypoints=websecure"
  - "traefik.http.routers.baudflow.tls.certresolver=letsencrypt"
  - "traefik.http.services.baudflow.loadbalancer.server.port=4000"
```

With either proxy, keep `:4000` on the internal Docker network — do not publish it
on the host. `PHX_HOST` must match the host in the proxy rule, or generated URLs
and the WebSocket upgrade check fail.

## Upgrading

Pull the new image tag and restart. Migrations run on boot, so the new pod
applies every pending `:up` migration (via `Baudflow.Release.migrate/0`) before
it serves.

```sh
docker pull ghcr.io/v1nvn/baudflow:%VERSION%
# restart on the new tag (the docker run / compose up / kubectl set image from above)
```

On Kubernetes, roll the Deployment and watch the rollout:

```sh
kubectl -n baudflow rollout status deploy/baudflow
```

Verify: `GET /health` returns `{"status":"ok"}` and the next scheduled run lands a
fresh measurement.

Downgrade is not supported. Ecto migrations may not be reversible — a `change/0`
that does not invert cleanly leaves the schema ahead of the old code, so do not
roll a tag back across a migration. Read the [changelog](../changelog/) before
jumping a major version; breaking changes are flagged there.

## Resource requirements

**Architectures:** `linux/amd64` and `linux/arm64` only. There is no `arm/v7`
image, so a 32-bit Raspberry Pi (Pi 3 or Zero 2 W on a 32-bit OS) is not
supported. A Pi 4 or Pi 5 on a 64-bit kernel runs.

**RAM / CPU:** no measured figures are published — TBD. baudflow is a single
Elixir release (one BEAM, one Repo pool, an Oban node, the endpoint) sized for a
modest home server, not a fleet. Measure it on the target hardware:

```sh
docker stats baudflow
```

Postgres is the larger share of the footprint. Every measurement row stores the
full Ookla payload in `raw_result`, so database size scales with measurement
count; budget disk against how often schedules run and how long `retention_days`
keeps them.

## Production checklist

- Set a strong `SECRET_KEY_BASE` (≥ 64 bytes).
- Point `PHX_HOST` at your real domain, behind your reverse proxy / TLS.
- Give the container a reachable Postgres and a persistent volume for the DB.
- Scrape `/metrics` and watch `/health`.
- Decide on retention and schedule DB backups.

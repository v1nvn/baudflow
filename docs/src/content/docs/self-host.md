---
title: Self host
description: "Deploy a self-hosted speed test with baudflow three ways: Docker run, Docker Compose, Kubernetes. Multi-arch non-root image, Ookla CLI bundled, no elevated capabilities, /health and /metrics included."
section: Guides
order: 10
article: true
updated: "2026-07-03"
---

A self-hosted speed test runs the Ookla Speedtest CLI from your own network, on
a schedule, and keeps every result. baudflow ships as a multi-arch, non-root
image: the CLI is already inside, with no elevated capabilities. Below: `docker run`,
Compose, and Kubernetes.

## You need

- **Postgres**: any reachable 14+ instance. baudflow owns its schema and migrates it on boot.
- **A secret**: `SECRET_KEY_BASE`, 64+ bytes. Generate with `openssl rand -base64 48`.
- **A host + port**: the container listens on `4000`; put your reverse proxy in front.

That's it: no config file, no volume mount, no `CAP_NET_RAW`. Everything else is
an env var. Pick a method.

## Docker

The fastest path. Bring your own Postgres and point the container at it:

```sh
# generate a signing key (>=64 bytes) once, reuse it across restarts
SECRET_KEY_BASE=$(openssl rand -base64 48)

docker run -d --name baudflow -p 4000:4000 \
  -e DATABASE_URL="ecto://postgres:postgres@host.docker.internal/baudflow" \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e PHX_HOST="baudflow.example.com" \
  ghcr.io/v1nvn/baudflow:%VERSION%

# open http://localhost:4000
```

The release runs migrations on boot, so the first start also lays down the
schema. Point a browser at port 4000; this is what you should see:

![baudflow running in a browser after a docker run: the live dashboard with readout, health heatmap, SLA compliance, and speed history.](../../assets/screenshots/dashboard.png)

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

A single manifest: Namespace, Deployment (auto-migrates), Service, Ingress. Uses
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

The release migrates on boot, so the manifest above is complete on its own. To
fail fast on a bad migration *before* the new pod serves traffic, run it as an
init container instead; that's how the project's own cluster rolls it out:

```yaml
      # add to the pod spec above to migrate before the app serves
      initContainers:
        - name: migrate
          image: ghcr.io/v1nvn/baudflow:%VERSION%
          command: ["/app/bin/baudflow"]
          args: ["eval", "Baudflow.Release.migrate()"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef: { name: baudflow-db, key: uri }
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef: { name: baudflow-secrets, key: secret-key-base }
```

The `/health` probe is already wired for liveness and readiness. For TLS,
termination lives in your Ingress; set `PHX_HOST` to the public hostname and
let the proxy hold the certificate. The full operational reference (retention,
backups, clustering) is in [Deployment](../deployment/).

## Environment

Only two are required. The rest are tuning:

```sh
DATABASE_URL      # required  -  ecto://user:pass@host/baudflow
SECRET_KEY_BASE   # required  -  mix phx.gen.secret  (or: openssl rand -base64 48)
PHX_HOST          # your public hostname, behind your reverse proxy
PORT=4000         # HTTP listen port
PHX_SERVER=true   # start the web server (releases)
SPEEDTEST_BIN     # bundled; override to pin your own Ookla binary
```

The complete list (`POOL_SIZE`, `ECTO_IPV6`, `DNS_CLUSTER_QUERY`) is in
[Environment variables](../environment-variables/).

## Health & metrics

- `GET /health` → `{"status":"ok"}`: point Uptime Kuma or a kube probe here.
- `GET /metrics` → Prometheus text, eight `baudflow_*` gauges. Scrape config and the full list are in the [metrics docs](../prometheus-metrics/).

Both bypass the browser pipeline deliberately, so scrapers get plain text with
no session/CSRF dance. The [feature walkthrough](/product/#features) covers what
those gauges feed.

## Next steps

- For retention, backups, and clustering, see [Deployment](../deployment/).
- The full env-var list is in [Environment variables](../environment-variables/).
- New here? Start with [Getting started](../getting-started/).

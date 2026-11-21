# QuakeWatch — DevOps Final Project

**QuakeWatch** is a Flask web application that shows real-time and historical earthquake
data from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/), with
Matplotlib graphs and a Bootstrap 5 UI.

Original application: <https://github.com/EduardUsatchev/QuakeWatch>

This repository takes the application through the full DevOps lifecycle:

| Phase | Topic | Status |
|-------|-------|--------|
| 1 | Docker — containerization, Docker Hub | ✅ |
| 2 | Kubernetes — Deployment, Service, HPA, probes, CronJob | ✅ |
| 3 | Helm, GitHub Actions CI/CD, ArgoCD (GitOps) | ⏳ |
| 4 | Terraform + AWS (VPC, EC2, K3s) | ⏳ |

---

## Project structure

```
quakewatch-devops/
├── app.py               # Application factory (create_app) and entry point
├── dashboard.py         # Blueprint with all routes
├── utils.py             # USGS API helpers, graph generation, Jinja2 filter
├── requirements.txt     # Pinned Python dependencies (incl. gunicorn)
├── static/              # Logo
├── templates/           # Jinja2 templates
├── Dockerfile           # Production image (python:3.12-slim + gunicorn, non-root)
├── .dockerignore        # Keeps the build context small
├── docker-compose.yml   # Local run with port mapping, healthcheck and log volume
└── k8s/                 # Kubernetes manifests (Phase 2)
```

## Endpoints

| Path | Description |
|------|-------------|
| `/` | Main page |
| `/graph-earthquakes` | Dashboard with graphs, top-5 and latest earthquake |
| `/health` | Health check (JSON) — used by Docker / Kubernetes probes |
| `/ping` | Returns `pong` |
| `/status`, `/info` | Service info (JSON) |
| `/telaviv-earthquakes` | Raw USGS data around Tel Aviv, last 30 days |

---

## Phase 1 — Docker

### Prerequisites

- Docker Engine or Docker Desktop (with Compose v2: `docker compose`)
- A Docker Hub account (here: `yuraodegov`)

### Image design

- **Base:** `python:3.12-slim` — small Debian image with Python.
- **Server:** `gunicorn` (production WSGI server) instead of Flask's built-in dev server.
  The app uses an application factory, so the entry point is `app:create_app()`.
- **Layer caching:** `requirements.txt` is copied and installed before the source code,
  so code changes don't reinstall dependencies.
- **Security:** runs as unprivileged user `appuser` (UID 10001).
- **Health:** `HEALTHCHECK` calls `/health` every 30 s.
- **Port:** 5000 (configurable with the `PORT` environment variable).

### Build and tag

```bash
docker build -t yuraodegov/quakewatch:1.0.0 .
docker tag yuraodegov/quakewatch:1.0.0 yuraodegov/quakewatch:latest
docker images yuraodegov/quakewatch
```

### Run with `docker run`

```bash
docker run -d --name quakewatch -p 5000:5000 yuraodegov/quakewatch:1.0.0
docker ps                     # STATUS should become "(healthy)" after ~15 s
curl http://localhost:5000/health
docker logs -f quakewatch
docker rm -f quakewatch       # stop and remove
```

### Run with Docker Compose

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f
docker compose down           # add -v to also delete the logs volume
```

Open <http://localhost:5000> in the browser.

### Push to Docker Hub

```bash
docker login -u yuraodegov
docker push yuraodegov/quakewatch:1.0.0
docker push yuraodegov/quakewatch:latest
```

Image: <https://hub.docker.com/r/yuraodegov/quakewatch>

Pull and run anywhere:

```bash
docker run -d -p 5000:5000 yuraodegov/quakewatch:latest
```

### Run without Docker (development)

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py                 # Flask dev server on http://127.0.0.1:5000
```

---

## Phase 2 — Kubernetes

### Manifests (`k8s/`)

| File | Resource | Purpose |
|------|----------|---------|
| `00-namespace.yaml` | Namespace `quakewatch` | Keeps all project resources together |
| `01-configmap.yaml` | ConfigMap `quakewatch-config` | `PORT`, `APP_ENV`, `HEALTHCHECK_URL` |
| `02-secret.yaml` | Secret `quakewatch-secret` | `SECRET_KEY` (demo value) |
| `03-deployment.yaml` | Deployment `quakewatch` (+ ReplicaSet) | 2 replicas, probes, requests/limits, env from ConfigMap and Secret |
| `04-service.yaml` | Service `quakewatch` (NodePort 30500) | Exposes the app outside the cluster |
| `05-hpa.yaml` | HorizontalPodAutoscaler | 2-5 replicas at 70% CPU of the request |
| `06-cronjob.yaml` | CronJob `quakewatch-healthcheck` | Every 5 min calls `/health` from inside the cluster |

The files are numbered in apply order: the namespace first, then the ConfigMap and
Secret the Deployment refers to.

### Design

- **High availability:** 2 replicas minimum; rolling updates with `maxUnavailable: 0`,
  so a new pod is ready before an old one is removed.
- **Probes:** readiness and liveness both call `GET /health` on port 5000.
  Readiness keeps a pod out of the Service until gunicorn answers; liveness restarts
  a container that stops answering.
- **Resources:** requests `100m` CPU / `128Mi` memory (the HPA computes utilization from
  the CPU request), limits `500m` / `512Mi` (Matplotlib needs memory headroom).
- **Configuration:** `PORT` comes from the ConfigMap and is used by the Dockerfile
  `CMD` (`gunicorn --bind 0.0.0.0:${PORT}`).
- **Secret:** the application does not use a secret yet; `SECRET_KEY` shows how one is
  injected. The value in git is a demo value — real secrets must not be committed
  (use `kubectl create secret` or a tool like Sealed Secrets / External Secrets).
- **Health-check CronJob:** a `busybox` pod runs `wget` against the Service DNS name
  `quakewatch.quakewatch.svc.cluster.local:5000/health`. On failure it exits with code 1,
  so the Job is marked `Failed` and is visible in `kubectl get jobs`.

### Prerequisites

- Docker Desktop with Kubernetes enabled (**Settings → Kubernetes → Enable Kubernetes**)
- `kubectl` and `helm` (for metrics-server)

Check the cluster:

```bash
kubectl get nodes          # all nodes Ready
```

### Install metrics-server (required by the HPA)

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args={--kubelet-insecure-tls}
```

`--kubelet-insecure-tls` is needed on Docker Desktop: the kubelet certificates are
self-signed.

### Deploy

```bash
kubectl apply -f k8s/
kubectl config set-context --current --namespace=quakewatch
kubectl get pods -w                     # wait for 2/2 pods Running 1/1
kubectl get deploy,rs,svc,hpa,cronjob
```

`kubectl apply -f k8s/` applies the files in alphabetical order, which is the numbered
order above.

### Open the application

```bash
kubectl port-forward svc/quakewatch 5000:5000
```

Open <http://localhost:5000>. The Service is a NodePort (`30500`), but Docker Desktop in
`kind` mode does not map node ports to `localhost`, so `port-forward` is used locally.
On a cluster with reachable nodes the app is at `http://<node-ip>:30500`.

### Verify

```bash
# Autoscaler: current CPU vs target
kubectl get hpa                         # cpu: 1%/70%, 2 replicas

# Run the health check now instead of waiting for the schedule
kubectl create job healthcheck-manual --from=cronjob/quakewatch-healthcheck
kubectl logs job/healthcheck-manual     # OK: QuakeWatch is up

# The check detects an outage
kubectl scale deploy quakewatch --replicas=0
kubectl create job healthcheck-fail --from=cronjob/quakewatch-healthcheck
kubectl logs job/healthcheck-fail       # FAIL: QuakeWatch is not responding
kubectl scale deploy quakewatch --replicas=2
kubectl get jobs                        # Complete / Failed

kubectl delete job healthcheck-manual healthcheck-fail
```

### Clean up

```bash
kubectl delete -f k8s/
helm uninstall metrics-server -n kube-system
kubectl config set-context --current --namespace=default
```

## Notes

- The app needs outbound internet access to `earthquake.usgs.gov`; without it the
  graph pages return HTTP 500, while `/`, `/health` and `/ping` still work.
- Application log files are written to `/app/logs` inside the container
  (persisted to the `quakewatch-logs` volume when using Compose).

# QuakeWatch — DevOps Final Project

**QuakeWatch** is a Flask web application that shows real-time and historical earthquake
data from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/), with
Matplotlib graphs and a Bootstrap 5 UI.

Original application: <https://github.com/EduardUsatchev/QuakeWatch>

This repository takes the application through the full DevOps lifecycle:

| Phase | Topic | Status |
|-------|-------|--------|
| 1 | Docker — containerization, Docker Hub | ✅ |
| 2 | Kubernetes — Deployment, Service, HPA, probes, CronJob | ⏳ |
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
└── docker-compose.yml   # Local run with port mapping, healthcheck and log volume
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

## Notes

- The app needs outbound internet access to `earthquake.usgs.gov`; without it the
  graph pages return HTTP 500, while `/`, `/health` and `/ping` still work.
- Application log files are written to `/app/logs` inside the container
  (persisted to the `quakewatch-logs` volume when using Compose).

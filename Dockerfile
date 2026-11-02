# QuakeWatch - Flask earthquake dashboard
# Production image: python slim base + gunicorn WSGI server, runs as non-root.

FROM python:3.12-slim

# Python runtime settings:
#  - no .pyc files inside the container
#  - unbuffered stdout/stderr so logs show up immediately in `docker logs`
#  - matplotlib cache dir must be writable by the non-root user
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    MPLCONFIGDIR=/tmp/matplotlib \
    PORT=5000

WORKDIR /app

# Install dependencies first: this layer is cached until requirements.txt changes
COPY requirements.txt .
RUN pip install -r requirements.txt

# Create an unprivileged user to run the app
RUN useradd --create-home --uid 10001 appuser

# Copy application code (filtered by .dockerignore)
COPY --chown=appuser:appuser . .

# The app writes rotating log files to ./logs at startup
RUN mkdir -p /app/logs && chown appuser:appuser /app/logs

USER appuser

EXPOSE 5000

# Container-level health check (no curl in slim image, so use Python stdlib)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=4).status == 200 else 1)"

# app.py exposes an application factory, so gunicorn calls create_app()
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --timeout 60 --access-logfile - 'app:create_app()'"]

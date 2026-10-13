FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY --chown=10001:10001 requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=10001:10001 app.py .
COPY --chown=10001:10001 templates ./templates

RUN useradd --system --uid 10001 appuser
USER 10001

EXPOSE 8080

CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:8080", "--access-logfile", "-", "--error-logfile", "-", "app:app"]

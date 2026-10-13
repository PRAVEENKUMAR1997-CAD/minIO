FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN useradd --system --uid 10001 --no-create-home appuser

COPY --chown=appuser:appuser requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appuser app.py .
COPY --chown=appuser:appuser templates ./templates
COPY --chown=appuser:appuser static ./static

USER appuser

EXPOSE 8080

CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:8080", "--access-logfile", "-", "--error-logfile", "-", "app:app"]

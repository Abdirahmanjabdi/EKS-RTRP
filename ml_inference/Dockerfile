# --- Stage 1: Builder ---
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt


# --- Stage 2: Runtime ---
FROM python:3.12-slim AS runtime

WORKDIR /app

RUN useradd -m -u 10001 appuser

COPY --from=builder --chown=appuser:appuser /app/deps /usr/local/lib/python3.12/site-packages

COPY --chown=appuser:appuser main.py .

USER appuser

EXPOSE 8002

CMD ["python", "main.py"]

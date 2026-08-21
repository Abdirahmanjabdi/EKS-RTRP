# --- Stage 1: Builder ---
FROM python:3.12-slim AS builder

WORKDIR /app


COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt


# --- Stage 2: Runtime ---
FROM python:3.12-slim AS runtime

WORKDIR /app

# 1. Create the non-root user first so we can reference it in --chown
RUN useradd -m -u 10001 appuser

# 2. Copy installed python dependencies with correct ownership set at copy time (#1)
COPY --from=builder --chown=appuser:appuser /app/deps /usr/local/lib/python3.12/site-packages

# 3. Copy only the specific application source code required to run (#3)
COPY --chown=appuser:appuser main.py .

# 4. Switch to the non-root user
USER appuser

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
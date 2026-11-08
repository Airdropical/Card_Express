FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_ENV=production \
    PYTHONPATH=/app/backend \
    DATA_DIR=/app/backend/data

WORKDIR /app
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini ./alembic.ini
COPY backend ./backend
COPY data ./data
COPY frontend ./frontend

# Legacy server builds still create DATA_DIR during import (including Alembic).
# Make that path writable before dropping privileges to the non-root app user.
RUN mkdir -p /app/backend/data && chown -R 10001:10001 /app/backend/data

USER 10001:10001
EXPOSE 8080
CMD ["sh", "backend/entrypoint.sh"]

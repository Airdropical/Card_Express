FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 DATA_DIR=/data APP_ENV=production
WORKDIR /app
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --system --uid 10001 appuser \
    && mkdir -p /data && chown appuser:appuser /data
COPY backend/server.py ./server.py
COPY backend/ai_prompts ./ai_prompts
USER appuser
EXPOSE 8787
CMD ["python", "server.py"]

FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt .

RUN apk upgrade --no-cache && \
    pip install --no-cache-dir -r requirements.txt && \
    addgroup -S appgroup && \
    adduser -S appuser -G appgroup && \
    chown -R appuser:appgroup /app

COPY app ./app

EXPOSE 8000

USER appuser

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
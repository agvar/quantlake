# Slim base -- ~50MB uncompressed vs ~1GB for full python:3.11
FROM public.ecr.aws/docker/library/python:3.11-slim

# Non-root user for security (Fargate doesn't require but exam-worthy)
RUN useradd --system --uid 1001 --home-dir /app app
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

USER app

# Fargate sends SIGTERM before killing; our code handles it for clean flush.
STOPSIGNAL SIGTERM

CMD ["python", "-u", "main.py"]

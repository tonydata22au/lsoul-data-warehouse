FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Run as an unprivileged user
RUN useradd --system --uid 10001 --no-create-home app
USER app

EXPOSE 8080

# Cloud Run sends requests to $PORT. gunicorn's own timeout is off, so the Cloud Run request timeout applies.
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app_runner:app

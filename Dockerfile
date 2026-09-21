# ---- build stage ----
FROM python:3.11-slim AS build
WORKDIR /app
COPY app/requirements.txt .
# Install into the build image's system site-packages
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .

# ---- runtime stage ----
FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app

# Copy both the interpreter's site-packages AND the app's binary deps
COPY --from=build /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=build /usr/local/bin/uvicorn /usr/local/bin/uvicorn
COPY --from=build /app /app

ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages
ENV PYTHONUNBUFFERED=1
ENV APP_VERSION=0.1.0

USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
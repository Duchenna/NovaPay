FROM python:3.12-slim AS build
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
COPY app/ .

FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app
COPY --from=build /install /usr/local
COPY --from=build /app /app
USER nonroot:nonroot
EXPOSE 8080
ENV APP_VERSION=0.1.0 PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
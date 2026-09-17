import os, json, time, logging
from fastapi import FastAPI, HTTPException, Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="NovaPay Wallet Service")
VERSION = os.getenv("APP_VERSION", "0.1.0")
START = time.time()

wallet_requests = Counter("wallet_requests_total", "Wallet lookups", ["status"])

class JsonFormatter(logging.Formatter):
    def format(self, r):
        return json.dumps({
            "ts": self.formatTime(r), "level": r.levelname,
            "msg": r.getMessage(), "svc": "wallet", "ver": VERSION
        })

log = logging.getLogger("wallet")
h = logging.StreamHandler(); h.setFormatter(JsonFormatter())
log.addHandler(h); log.setLevel(logging.INFO)

FAKE_DB = {"1001": {"id": "1001", "balance_kobo": 250000, "kyc_tier": 2}}

@app.get("/health")
def health(): return {"status": "ok"}

@app.get("/ready")
def ready(): return {"status": "ready", "uptime_s": round(time.time()-START)}

@app.get("/version")
def version(): return {"version": VERSION, "commit": os.getenv("GIT_SHA", "dev")}

@app.get("/wallets/{wallet_id}")
def get_wallet(wallet_id: str):
    w = FAKE_DB.get(wallet_id)
    if not w:
        wallet_requests.labels("404").inc()
        log.warning(f"wallet_not_found id={wallet_id}")
        raise HTTPException(404, "wallet not found")
    wallet_requests.labels("200").inc()
    return w

@app.get("/metrics")
def metrics(): return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
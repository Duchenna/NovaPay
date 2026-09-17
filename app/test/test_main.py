from fastapi.testclient import TestClient
from app.main import app
client = TestClient(app)

def test_health():  assert client.get("/health").json()["status"] == "ok"
def test_version(): assert "version" in client.get("/version").json()
def test_wallet_found():  assert client.get("/wallets/1001").json()["id"] == "1001"
def test_wallet_missing(): assert client.get("/wallets/9999").status_code == 404
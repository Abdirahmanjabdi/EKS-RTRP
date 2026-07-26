from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_create_trade_valid():
    payload = {
        "symbol": "AAPL",
        "side": "buy",
        "quantity": 100,
        "price": 150.02,
        "timestamp": "2026-07-26T14:30:00Z"
    }
    response = client.post("/trades", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "acknowledged"
    assert data["data"]["symbol"] == "AAPL"

def test_create_trade_invalid_negative_quantity():
    payload = {
        "symbol": "AAPL",
        "side": "buy",
        "quantity": -10,
        "price": 150.02,
        "timestamp": "2026-07-26T14:30:00Z"
    }
    response = client.post("/trades", json=payload)
    assert response.status_code == 422
from unittest.mock import patch

from fastapi.testclient import TestClient
from pika.exceptions import AMQPConnectionError

from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

# Patched as "main.publish_trade_created", not "pika...": mock.patch replaces
# the name in the module that calls it (main.py), not where it's defined.
@patch("main.publish_trade_created", return_value="test-event-id")
def test_create_trade_valid(mock_publish):
    payload = {
        "symbol": "AAPL",
        "side": "buy",
        "quantity": 100,
        "price": 150.02,
        "timestamp": "2026-07-26T14:30:00Z"
    }
    response = client.post("/trades", json=payload)
    assert response.status_code == 202
    data = response.json()
    assert data["status"] == "accepted"
    assert data["event_id"] == "test-event-id"
    assert data["data"]["symbol"] == "AAPL"
    mock_publish.assert_called_once()

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

@patch("main.publish_trade_created", side_effect=AMQPConnectionError())
def test_create_trade_broker_unavailable(mock_publish):
    payload = {
        "symbol": "AAPL",
        "side": "buy",
        "quantity": 100,
        "price": 150.02,
        "timestamp": "2026-07-26T14:30:00Z"
    }
    response = client.post("/trades", json=payload)
    assert response.status_code == 503
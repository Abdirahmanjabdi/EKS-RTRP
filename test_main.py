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
@patch("main.persist_trade")
@patch("main.publish_trade_created", return_value="test-event-id")
def test_create_trade_valid(mock_publish, mock_persist):
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
    mock_persist.assert_called_once()

# Postgres persistence is a durable log on top of the broker publish, not a
# second gate — a trade that's already been accepted by RabbitMQ should
# still return 202 even if the database write afterward fails.
@patch("main.persist_trade", side_effect=Exception("db unreachable"))
@patch("main.publish_trade_created", return_value="test-event-id")
def test_create_trade_survives_db_failure(mock_publish, mock_persist):
    payload = {
        "symbol": "AAPL",
        "side": "buy",
        "quantity": 100,
        "price": 150.02,
        "timestamp": "2026-07-26T14:30:00Z"
    }
    response = client.post("/trades", json=payload)
    assert response.status_code == 202
    assert response.json()["status"] == "accepted"

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

@patch("main.get_redis")
def test_get_risk_cache_hit(mock_get_redis):
    mock_get_redis.return_value.get.return_value = "15025.0"
    response = client.get("/risk/AAPL")
    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "AAPL"
    assert data["exposure"] == 15025.0
    assert data["source"] == "cache"
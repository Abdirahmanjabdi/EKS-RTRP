import json
import os
import ssl
import uuid
from datetime import datetime, timezone
from enum import Enum
from urllib.parse import urlparse

import pika
import uvicorn
from fastapi import FastAPI, HTTPException, status
from pika.exceptions import AMQPError
from pydantic import BaseModel, Field

app = FastAPI(title="Trade API v0", version="0.1.0")

EXCHANGE_NAME = "rtrp.trades"
ROUTING_KEY = "trade.created"

class Side(str, Enum):
    BUY = "buy"
    SELL = "sell"

class Trade(BaseModel):
    symbol: str = Field(..., min_length=1, description="The instrument symbol, e.g., AAPL, EURUSD")
    side: Side = Field(..., description="Order side: buy or sell")
    quantity: float = Field(..., gt=0, description="Execution quantity, must be greater than 0")
    price: float = Field(..., gt=0, description="Execution price, must be greater than 0")
    timestamp: datetime = Field(..., description="Execution timestamp in UTC")

def publish_trade_created(trade: Trade) -> str:
    event_id = str(uuid.uuid4())
    envelope = {
        "event_id": event_id,
        "event_type": ROUTING_KEY,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "schema_version": 1,
        "data": json.loads(trade.model_dump_json()),
    }

    broker_url = urlparse(os.environ["RABBITMQ_URL"])
    credentials = pika.PlainCredentials(
        os.environ["RABBITMQ_USERNAME"], os.environ["RABBITMQ_PASSWORD"]
    )
    # New connection per request — pika's BlockingConnection isn't
    # thread-safe, and FastAPI runs sync routes in a thread pool.
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=broker_url.hostname,
            port=broker_url.port or 5671,
            credentials=credentials,
            ssl_options=pika.SSLOptions(ssl.create_default_context()),
        )
    )
    try:
        channel = connection.channel()
        channel.confirm_delivery()
        channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type="topic", durable=True)
        channel.basic_publish(
            exchange=EXCHANGE_NAME,
            routing_key=ROUTING_KEY,
            body=json.dumps(envelope),
            properties=pika.BasicProperties(content_type="application/json", delivery_mode=2),
            mandatory=True,
        )
    finally:
        connection.close()

    return event_id

@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    return {"status": "ok"}

@app.post("/trades", status_code=status.HTTP_202_ACCEPTED)
def create_trade(trade: Trade):
    try:
        event_id = publish_trade_created(trade)
    except AMQPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="trade event broker unavailable",
        ) from exc

    return {
        "status": "accepted",
        "event_id": event_id,
        "data": trade,
    }

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
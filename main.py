import json
import logging
import os
import ssl
import uuid
from datetime import datetime, timezone
from enum import Enum
from urllib.parse import urlparse

import pika
import redis
import uvicorn
from fastapi import FastAPI, HTTPException, Response, status
from pika.exceptions import AMQPError
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Float, String, create_engine, desc
from sqlalchemy.orm import declarative_base, sessionmaker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("trade-api")

app = FastAPI(title="Trade API v0", version="0.1.0")

EXCHANGE_NAME = "rtrp.trades"
ROUTING_KEY = "trade.created"

TRADES_RECEIVED = Counter("trades_received_total", "Total trades accepted by the API")
TRADE_PUBLISH_DURATION = Histogram(
    "trade_publish_duration_seconds", "Time to publish a trade event to RabbitMQ"
)

Base = declarative_base()

class TradeRecord(Base):
    __tablename__ = "trades"
    event_id = Column(String, primary_key=True)
    symbol = Column(String, nullable=False)
    side = Column(String, nullable=False)
    quantity = Column(Float, nullable=False)
    price = Column(Float, nullable=False)
    timestamp = Column(DateTime, nullable=False)

class RiskComputation(Base):
    __tablename__ = "risk_computations"
    event_id = Column(String, primary_key=True)
    symbol = Column(String, nullable=False, index=True)
    exposure = Column(Float, nullable=False)
    computed_at = Column(DateTime, nullable=False)

# Created once, not per-request: unlike pika's BlockingConnection, SQLAlchemy's
# engine manages its own connection pool and is meant to be shared. Lazy so
# importing this module (e.g. under test) never requires POSTGRES_* to be set.
_engine = None

def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(
            f"postgresql+psycopg2://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
            f"@{os.environ['POSTGRES_HOST']}:{os.environ['POSTGRES_PORT']}/{os.environ['POSTGRES_DB']}"
        )
        Base.metadata.create_all(_engine)
    return _engine

def get_redis() -> redis.Redis:
    return redis.Redis(
        host=os.environ["REDIS_HOST"],
        port=int(os.environ["REDIS_PORT"]),
        password=os.environ["REDIS_AUTH_TOKEN"],
        ssl=True,
        decode_responses=True,
    )

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

def persist_trade(event_id: str, trade: Trade) -> None:
    session = sessionmaker(bind=get_engine())()
    try:
        session.add(TradeRecord(
            event_id=event_id,
            symbol=trade.symbol,
            side=trade.side.value,
            quantity=trade.quantity,
            price=trade.price,
            timestamp=trade.timestamp,
        ))
        session.commit()
    finally:
        session.close()

@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.post("/trades", status_code=status.HTTP_202_ACCEPTED)
def create_trade(trade: Trade):
    with TRADE_PUBLISH_DURATION.time():
        try:
            event_id = publish_trade_created(trade)
        except AMQPError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="trade event broker unavailable",
            ) from exc

    TRADES_RECEIVED.inc()

    # Publishing to RabbitMQ is the source of truth for "did this trade
    # enter the system" — Postgres is a durable log on top of that, not a
    # second gate. A failed write here is logged, not raised, so it never
    # turns an already-accepted trade into a client-visible error.
    try:
        persist_trade(event_id, trade)
    except Exception:
        logger.exception("failed to persist trade to Postgres")

    return {
        "status": "accepted",
        "event_id": event_id,
        "data": trade,
    }

@app.get("/risk/{symbol}")
def get_risk(symbol: str):
    cache = get_redis()
    cached = cache.get(f"risk:latest:{symbol}")
    if cached is not None:
        return {"symbol": symbol, "exposure": float(cached), "source": "cache"}

    session = sessionmaker(bind=get_engine())()
    try:
        row = (
            session.query(RiskComputation)
            .filter(RiskComputation.symbol == symbol)
            .order_by(desc(RiskComputation.computed_at))
            .first()
        )
    finally:
        session.close()

    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="no risk computed for this symbol yet")

    return {"symbol": symbol, "exposure": row.exposure, "source": "database"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
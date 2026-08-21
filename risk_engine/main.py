import json
import logging
import os
import ssl
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

import pika
import redis
from pika.exceptions import AMQPError
from prometheus_client import Counter, Gauge, Histogram, start_http_server
from sqlalchemy import Column, DateTime, Float, String, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("risk-engine")

EXCHANGE_NAME = "rtrp.trades"
ROUTING_KEY = "trade.created"
QUEUE_NAME = "risk-engine.trade-events"
METRICS_PORT = 8001

# Separate exchange from rtrp.trades on purpose — that one is trade lifecycle
# events; this one is risk-computation results, a different kind of thing
# with different consumers (M4's ML Inference and Alerting, not built yet).
RISK_EXCHANGE_NAME = "rtrp.risk"
RISK_ROUTING_KEY = "risk.computed"

EVENTS_PROCESSED = Counter("risk_events_processed_total", "Total trade events processed")
PROCESSING_DURATION = Histogram(
    "risk_processing_duration_seconds", "Time to compute and persist risk for one event"
)
LATEST_EXPOSURE = Gauge(
    "risk_latest_exposure", "Most recently computed notional exposure per symbol", ["symbol"]
)

Base = declarative_base()

class RiskComputation(Base):
    __tablename__ = "risk_computations"
    event_id = Column(String, primary_key=True)
    symbol = Column(String, nullable=False, index=True)
    exposure = Column(Float, nullable=False)
    computed_at = Column(DateTime, nullable=False)

# Same reasoning as Trade API: SQLAlchemy's engine pools connections and is
# meant to be created once, unlike the per-message pika connection below.
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


def compute_notional_exposure(trade: dict) -> float:
    # Placeholder — proves the pipeline end to end. Real VaR/PnL comes later.
    return trade["quantity"] * trade["price"]


def persist_and_cache(event_id: str, symbol: str, exposure: float) -> None:
    session = sessionmaker(bind=get_engine())()
    try:
        session.add(RiskComputation(
            event_id=event_id,
            symbol=symbol,
            exposure=exposure,
            computed_at=datetime.now(timezone.utc),
        ))
        session.commit()
    finally:
        session.close()

    get_redis().set(f"risk:latest:{symbol}", exposure)


def publish_risk_computed(channel, trade_event_id: str, symbol: str, exposure: float) -> None:
    envelope = {
        "event_id": str(uuid.uuid4()),
        "event_type": RISK_ROUTING_KEY,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "schema_version": 1,
        "data": {
            "trade_event_id": trade_event_id,
            "symbol": symbol,
            "exposure": exposure,
        },
    }
    channel.basic_publish(
        exchange=RISK_EXCHANGE_NAME,
        routing_key=RISK_ROUTING_KEY,
        body=json.dumps(envelope),
        properties=pika.BasicProperties(content_type="application/json", delivery_mode=2),
        mandatory=True,
    )


def handle_message(channel, method, properties, body):
    with PROCESSING_DURATION.time():
        try:
            envelope = json.loads(body)
            trade = envelope["data"]
            event_id = envelope.get("event_id")
            symbol = trade.get("symbol")
            exposure = compute_notional_exposure(trade)

            logger.info(
                "risk computed event_id=%s symbol=%s exposure=%.2f",
                event_id, symbol, exposure,
            )

            # Same resilience stance as Trade API: the message is only acked
            # after persistence succeeds, so a DB/cache outage causes a
            # requeue-and-retry rather than a silently lost computation —
            # unlike the API's write, this one isn't allowed to fail quietly.
            persist_and_cache(event_id, symbol, exposure)
            LATEST_EXPOSURE.labels(symbol=symbol).set(exposure)
            EVENTS_PROCESSED.inc()

            # Downstream of persistence, not before: ML Inference and
            # Alerting only need to see risk that's already durably
            # recorded, and a failed publish here shouldn't cause the
            # already-computed, already-persisted risk to be requeued.
            try:
                publish_risk_computed(channel, event_id, symbol, exposure)
            except Exception:
                logger.exception("failed to publish risk.computed, continuing")

            channel.basic_ack(delivery_tag=method.delivery_tag)
        except Exception:
            logger.exception("failed to process message, requeueing")
            channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)


def connect() -> pika.BlockingConnection:
    broker_url = urlparse(os.environ["RABBITMQ_URL"])
    credentials = pika.PlainCredentials(
        os.environ["RABBITMQ_USERNAME"], os.environ["RABBITMQ_PASSWORD"]
    )
    return pika.BlockingConnection(
        pika.ConnectionParameters(
            host=broker_url.hostname,
            port=broker_url.port or 5671,
            credentials=credentials,
            ssl_options=pika.SSLOptions(ssl.create_default_context()),
            heartbeat=30,
        )
    )


def main():
    start_http_server(METRICS_PORT)
    logger.info("metrics server listening on :%d", METRICS_PORT)

    while True:
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            # The consumer owns the queue, not the producer — Trade API's
            # main.py only ever talks to the exchange, never this queue.
            channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.queue_bind(exchange=EXCHANGE_NAME, queue=QUEUE_NAME, routing_key=ROUTING_KEY)
            # Declared here too, not just by ML Inference/Alerting's consumers
            # — same reasoning as EXCHANGE_NAME above: whoever publishes
            # first shouldn't have to trust that a consumer already exists.
            channel.exchange_declare(exchange=RISK_EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.basic_qos(prefetch_count=10)
            channel.basic_consume(queue=QUEUE_NAME, on_message_callback=handle_message, auto_ack=False)

            logger.info("connected, consuming from %s", QUEUE_NAME)
            channel.start_consuming()
        except AMQPError:
            logger.exception("broker connection lost, reconnecting in 5s")
            time.sleep(5)


if __name__ == "__main__":
    main()

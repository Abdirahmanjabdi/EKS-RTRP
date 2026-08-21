import json
import logging
import os
import ssl
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

import numpy as np
import pika
import redis
from pika.exceptions import AMQPError
from prometheus_client import Counter, Histogram, start_http_server
from sklearn.ensemble import IsolationForest
from sqlalchemy import Column, DateTime, Float, String, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("ml-inference")

RISK_EXCHANGE_NAME = "rtrp.risk"
RISK_ROUTING_KEY = "risk.computed"
QUEUE_NAME = "ml-inference.risk-events"

ALERTS_EXCHANGE_NAME = "rtrp.alerts"
ALERT_ROUTING_KEY = "alert.triggered"

METRICS_PORT = 8002
WINDOW_SIZE = 50
MIN_SAMPLES = 10  # below this, there's no history to compare against —
                  # detection is skipped rather than false-flagging on nothing.

EVENTS_PROCESSED = Counter("ml_events_processed_total", "Total risk events scored")
ANOMALIES_DETECTED = Counter("ml_anomalies_detected_total", "Total anomalies flagged")
INFERENCE_DURATION = Histogram(
    "ml_inference_duration_seconds", "Time to fit and score one risk event"
)

Base = declarative_base()

class Anomaly(Base):
    __tablename__ = "anomalies"
    event_id = Column(String, primary_key=True)
    symbol = Column(String, nullable=False, index=True)
    exposure = Column(Float, nullable=False)
    detected_at = Column(DateTime, nullable=False)

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


def get_window(r: redis.Redis, symbol: str) -> list:
    return [float(v) for v in r.lrange(f"risk:history:{symbol}", 0, -1)]

def update_window(r: redis.Redis, symbol: str, exposure: float) -> None:
    key = f"risk:history:{symbol}"
    r.lpush(key, exposure)
    r.ltrim(key, 0, WINDOW_SIZE - 1)


def is_anomaly(window: list, new_value: float) -> bool:
    # Fit on the window as it stood *before* this point, then score the new
    # point against that baseline — scoring a point against a model fit
    # including itself would bias every point toward looking normal.
    X = np.array(window).reshape(-1, 1)
    model = IsolationForest(contamination=0.1, random_state=42)
    model.fit(X)
    prediction = model.predict([[new_value]])
    return bool(prediction[0] == -1)


def persist_anomaly(event_id: str, symbol: str, exposure: float) -> None:
    session = sessionmaker(bind=get_engine())()
    try:
        session.add(Anomaly(
            event_id=event_id,
            symbol=symbol,
            exposure=exposure,
            detected_at=datetime.now(timezone.utc),
        ))
        session.commit()
    finally:
        session.close()


def publish_alert(channel, trade_event_id: str, symbol: str, exposure: float) -> None:
    envelope = {
        "event_id": str(uuid.uuid4()),
        "event_type": "ml_anomaly",
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "schema_version": 1,
        "data": {
            "trade_event_id": trade_event_id,
            "symbol": symbol,
            "exposure": exposure,
        },
    }
    channel.basic_publish(
        exchange=ALERTS_EXCHANGE_NAME,
        routing_key=ALERT_ROUTING_KEY,
        body=json.dumps(envelope),
        properties=pika.BasicProperties(content_type="application/json", delivery_mode=2),
        mandatory=True,
    )


def handle_message(channel, method, properties, body):
    with INFERENCE_DURATION.time():
        try:
            envelope = json.loads(body)
            data = envelope["data"]
            symbol = data["symbol"]
            exposure = data["exposure"]
            trade_event_id = data.get("trade_event_id")

            r = get_redis()
            window = get_window(r, symbol)

            anomalous = len(window) >= MIN_SAMPLES and is_anomaly(window, exposure)
            update_window(r, symbol, exposure)

            if anomalous:
                logger.info("anomaly detected symbol=%s exposure=%.2f", symbol, exposure)
                persist_anomaly(envelope["event_id"], symbol, exposure)
                try:
                    publish_alert(channel, trade_event_id, symbol, exposure)
                except Exception:
                    logger.exception("failed to publish alert.triggered, continuing")
                ANOMALIES_DETECTED.inc()

            EVENTS_PROCESSED.inc()
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
            channel.exchange_declare(exchange=RISK_EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.exchange_declare(exchange=ALERTS_EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.queue_bind(exchange=RISK_EXCHANGE_NAME, queue=QUEUE_NAME, routing_key=RISK_ROUTING_KEY)
            channel.basic_qos(prefetch_count=10)
            channel.basic_consume(queue=QUEUE_NAME, on_message_callback=handle_message, auto_ack=False)

            logger.info("connected, consuming from %s", QUEUE_NAME)
            channel.start_consuming()
        except AMQPError:
            logger.exception("broker connection lost, reconnecting in 5s")
            time.sleep(5)


if __name__ == "__main__":
    main()

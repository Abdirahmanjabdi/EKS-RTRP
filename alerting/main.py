import json
import logging
import os
import ssl
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

import boto3
import pika
from pika.exceptions import AMQPError
from prometheus_client import Counter, start_http_server
from sqlalchemy import Column, DateTime, Float, String, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("alerting")

RISK_EXCHANGE_NAME = "rtrp.risk"
RISK_ROUTING_KEY = "risk.computed"
ALERTS_EXCHANGE_NAME = "rtrp.alerts"
ALERT_ROUTING_KEY = "alert.triggered"
QUEUE_NAME = "alerting.events"

METRICS_PORT = 8003
ALERT_THRESHOLD = float(os.environ.get("ALERT_THRESHOLD_USD", "50000"))
AWS_REGION = os.environ.get("AWS_REGION", "eu-north-1")

ALERTS_SENT = Counter("alerts_sent_total", "Total alerts published to SNS", ["reason"])

Base = declarative_base()

class Alert(Base):
    __tablename__ = "alerts"
    id = Column(String, primary_key=True)
    symbol = Column(String, nullable=False, index=True)
    exposure = Column(Float, nullable=False)
    reason = Column(String, nullable=False)
    sent_at = Column(DateTime, nullable=False)

_engine = None
_sns_client = None

def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(
            f"postgresql+psycopg2://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
            f"@{os.environ['POSTGRES_HOST']}:{os.environ['POSTGRES_PORT']}/{os.environ['POSTGRES_DB']}"
        )
        Base.metadata.create_all(_engine)
    return _engine

def get_sns():
    global _sns_client
    if _sns_client is None:
        # No access keys anywhere — credentials come from the ECS task role
        # (aws_iam_role.task, unused since M1) via the container's metadata
        # endpoint. boto3 finds this automatically; region does not default
        # on ECS the way it does on Lambda, so it's passed explicitly.
        _sns_client = boto3.client("sns", region_name=AWS_REGION)
    return _sns_client


def persist_alert(symbol: str, exposure: float, reason: str) -> None:
    session = sessionmaker(bind=get_engine())()
    try:
        session.add(Alert(
            id=str(uuid.uuid4()),
            symbol=symbol,
            exposure=exposure,
            reason=reason,
            sent_at=datetime.now(timezone.utc),
        ))
        session.commit()
    finally:
        session.close()


def send_alert(symbol: str, exposure: float, reason: str, category: str) -> None:
    message = f"RTRP Alert: {symbol} exposure ${exposure:,.2f} — {reason}"
    get_sns().publish(
        TopicArn=os.environ["SNS_TOPIC_ARN"],
        Subject=f"RTRP Alert: {symbol}",
        Message=message,
    )
    persist_alert(symbol, exposure, reason)
    ALERTS_SENT.labels(reason=category).inc()
    logger.info("alert sent symbol=%s exposure=%.2f reason=%s", symbol, exposure, reason)


def handle_message(channel, method, properties, body):
    try:
        envelope = json.loads(body)
        event_type = envelope.get("event_type")
        data = envelope["data"]
        symbol = data["symbol"]
        exposure = data["exposure"]

        if event_type == RISK_ROUTING_KEY and exposure >= ALERT_THRESHOLD:
            send_alert(
                symbol, exposure,
                reason=f"exposure exceeds ${ALERT_THRESHOLD:,.2f} threshold",
                category="threshold",
            )
        elif event_type == "ml_anomaly":
            send_alert(
                symbol, exposure,
                reason="flagged as a statistical anomaly by ML Inference",
                category="ml_anomaly",
            )
        # risk.computed events under threshold are the common case — no
        # alert, no log noise, just ack and move on.

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
            channel.exchange_declare(exchange=RISK_EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.exchange_declare(exchange=ALERTS_EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            # One queue, two independent bindings — this is the actual
            # "fan-out" the milestone is named for: a threshold rule that
            # works even with zero ML history, and ML-flagged anomalies,
            # converging on the same notification path.
            channel.queue_bind(exchange=RISK_EXCHANGE_NAME, queue=QUEUE_NAME, routing_key=RISK_ROUTING_KEY)
            channel.queue_bind(exchange=ALERTS_EXCHANGE_NAME, queue=QUEUE_NAME, routing_key=ALERT_ROUTING_KEY)
            channel.basic_qos(prefetch_count=10)
            channel.basic_consume(queue=QUEUE_NAME, on_message_callback=handle_message, auto_ack=False)

            logger.info("connected, consuming from %s", QUEUE_NAME)
            channel.start_consuming()
        except AMQPError:
            logger.exception("broker connection lost, reconnecting in 5s")
            time.sleep(5)


if __name__ == "__main__":
    main()

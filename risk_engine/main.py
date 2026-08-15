import json
import logging
import os
import ssl
import time
from urllib.parse import urlparse

import pika
from pika.exceptions import AMQPError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("risk-engine")

EXCHANGE_NAME = "rtrp.trades"
ROUTING_KEY = "trade.created"
QUEUE_NAME = "risk-engine.trade-events"


def compute_notional_exposure(trade: dict) -> float:
    # Placeholder — proves the pipeline end to end. Real VaR/PnL comes later.
    return trade["quantity"] * trade["price"]


def handle_message(channel, method, properties, body):
    try:
        envelope = json.loads(body)
        trade = envelope["data"]
        exposure = compute_notional_exposure(trade)
        logger.info(
            "risk computed event_id=%s symbol=%s exposure=%.2f",
            envelope.get("event_id"), trade.get("symbol"), exposure,
        )
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
    while True:
        try:
            connection = connect()
            channel = connection.channel()
            # The consumer owns the queue, not the producer — Trade API's
            # main.py only ever talks to the exchange, never this queue.
            channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type="topic", durable=True)
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.queue_bind(exchange=EXCHANGE_NAME, queue=QUEUE_NAME, routing_key=ROUTING_KEY)
            channel.basic_qos(prefetch_count=10)
            channel.basic_consume(queue=QUEUE_NAME, on_message_callback=handle_message, auto_ack=False)

            logger.info("connected, consuming from %s", QUEUE_NAME)
            channel.start_consuming()
        except AMQPError:
            logger.exception("broker connection lost, reconnecting in 5s")
            time.sleep(5)


if __name__ == "__main__":
    main()

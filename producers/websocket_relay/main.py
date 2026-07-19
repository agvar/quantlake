"""
Finnhub WebSocket -> Kinesis relay.

Long-lived Fargate task: opens a WebSocket to Finnhub's trade feed,
subscribes to a configured list of tickers, and publishes each tick
as a Kinesis record on quantlake-market-events.

Environment:
- SECRET_ID              Secrets Manager secret containing FINNHUB_KEY
- TICKERS                Comma-separated symbols (e.g. AAPL,MSFT,NVDA)
- KINESIS_STREAM_NAME    Target Kinesis stream
- AWS_REGION             AWS region for Kinesis + Secrets Manager
"""

import asyncio
import hashlib
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone

import boto3
import websockets

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger(__name__)

SECRETS = boto3.client("secretsmanager")
KINESIS = boto3.client("kinesis")

SHUTDOWN = asyncio.Event()


def get_api_key(secret_id: str) -> str:
    response = SECRETS.get_secret_value(SecretId=secret_id)
    return json.loads(response["SecretString"])["FINNHUB_KEY"]


def publish_to_kinesis(stream: str, records: list[dict]) -> int:
    """PutRecords with symbol as partition key. Returns success count."""
    if not records:
        return 0
    BATCH = 500
    total_ok = 0
    for i in range(0, len(records), BATCH):
        chunk = records[i:i + BATCH]
        entries = [{
            "Data": json.dumps(r).encode("utf-8"),
            "PartitionKey": r.get("symbol", "UNKNOWN"),
        } for r in chunk]
        resp = KINESIS.put_records(StreamName=stream, Records=entries)
        failed = resp.get("FailedRecordCount", 0)
        total_ok += (len(chunk) - failed)
        if failed:
            LOG.warning("Kinesis: %d/%d records failed", failed, len(chunk))
    return total_ok


def normalize_tick(t: dict, symbol: str) -> dict:
    """Add provenance + dedup_key to a raw Finnhub tick."""
    # Finnhub tick shape: {"s": symbol, "p": price, "v": volume, "t": ms, "c": conditions}
    fetched_at = datetime.now(timezone.utc).isoformat()
    dedup_key = hashlib.sha256(
        f"{symbol}|{t.get('t')}|{t.get('p')}|{t.get('v')}".encode()
    ).hexdigest()[:16]
    return {
        "source": "finnhub_ws",
        "asset_class": "equity",
        "symbol": symbol,
        "price": t.get("p"),
        "volume": t.get("v"),
        "timestamp_ms": t.get("t"),
        "conditions": t.get("c", []),
        "fetched_at": fetched_at,
        "dedup_key": dedup_key,
    }


async def run_websocket(api_key: str, tickers: list[str], stream: str):
    """One WebSocket session. Returns when session ends (caller reconnects)."""
    url = f"wss://ws.finnhub.io?token={api_key}"
    async with websockets.connect(url, ping_interval=30, ping_timeout=10) as ws:
        # Subscribe to each ticker.
        for symbol in tickers:
            await ws.send(json.dumps({"type": "subscribe", "symbol": symbol}))
            LOG.info("Subscribed: %s", symbol)

        buffer = []
        last_flush = time.time()

        async for raw in ws:
            if SHUTDOWN.is_set():
                break

            msg = json.loads(raw)
            if msg.get("type") != "trade":
                continue  # ping/error/etc.

            for tick in msg.get("data", []):
                buffer.append(normalize_tick(tick, tick.get("s", "UNKNOWN")))

            # Flush every 100 records OR every 1 second, whichever first.
            now = time.time()
            if len(buffer) >= 100 or (buffer and now - last_flush >= 1.0):
                published = publish_to_kinesis(stream, buffer)
                LOG.info("Flushed %d ticks", published)
                buffer.clear()
                last_flush = now

        # Final flush before exit.
        if buffer:
            publish_to_kinesis(stream, buffer)
            LOG.info("Final flush: %d ticks", len(buffer))


async def main():
    secret_id  = os.environ["SECRET_ID"]
    tickers    = [t.strip().upper() for t in os.environ["TICKERS"].split(",")]
    stream     = os.environ["KINESIS_STREAM_NAME"]

    api_key = get_api_key(secret_id)
    LOG.info("Starting relay for %s -> %s", tickers, stream)

    # Reconnect loop with exponential backoff.
    backoff = 1
    while not SHUTDOWN.is_set():
        try:
            await run_websocket(api_key, tickers, stream)
            LOG.info("WebSocket closed normally; reconnecting")
            backoff = 1
        except Exception as exc:
            LOG.exception("WebSocket error: %s -- retrying in %ds", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60)  # cap at 60s


def _install_shutdown_handlers(loop):
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, SHUTDOWN.set)


if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    _install_shutdown_handlers(loop)
    try:
        loop.run_until_complete(main())
    finally:
        loop.close()
        LOG.info("Relay exited cleanly")
        sys.exit(0)

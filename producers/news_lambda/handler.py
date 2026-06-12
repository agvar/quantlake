"""
QuantLake news fetcher: Finnhub company-news -> S3 raw zone.

Similar contract to the bars fetcher, different schema and faster rate limit.

Local run:
  export RAW_BUCKET=quantlake-raw-<acct>
  export SECRET_ID=quantlake/api-keys/market-data-providers
  export TICKERS=AAPL,MSFT,NVDA
  export AWS_PROFILE=quantlake-admin
  python handler.py
"""

import hashlib
import json
import logging
import os
import time
import urllib.parse
import urllib.request
import urllib.error
from datetime import datetime, timedelta, timezone

import boto3

SECRETS = boto3.client("secretsmanager")
S3 = boto3.client("s3")

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

FINNHUB_BASE = "https://finnhub.io/api/v1/company-news"

# Finnhub free: 60/min. 1.1s sleep keeps us comfortably under it.
FINNHUB_REQUEST_INTERVAL_SECONDS = 1.1


def get_api_key(secret_id: str, key_name: str) -> str:
    response = SECRETS.get_secret_value(SecretId=secret_id)
    return json.loads(response["SecretString"])[key_name]


def fetch_news(symbol: str, api_key: str, days_back: int = 1) -> list[dict]:
    """Pull company-news for [today - days_back, today]."""
    today = datetime.now(timezone.utc).date()
    from_date = (today - timedelta(days=days_back)).isoformat()
    to_date = today.isoformat()

    params = {"symbol": symbol, "from": from_date, "to": to_date, "token": api_key}
    url = f"{FINNHUB_BASE}?{urllib.parse.urlencode(params)}"

    max_attempts = 4
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(url, timeout=20) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < max_attempts - 1:
                sleep_for = (2 ** attempt) + 0.5
                LOG.warning("429 for %s, retry %d in %.1fs", symbol, attempt + 1, sleep_for)
                time.sleep(sleep_for)
                continue
            raise
    raise RuntimeError(f"Exhausted retries for {symbol}")


def normalize_news(symbol: str, articles: list[dict]) -> list[dict]:
    """
    Finnhub returns a flat list of article dicts. We add our dedup_key + provenance
    fields and pass through everything else (raw-zone fidelity).
    """
    fetched_at = datetime.now(timezone.utc).isoformat()
    out = []
    for art in articles:
        url = art.get("url", "")
        published_at = art.get("datetime", 0)
        dedup_key = hashlib.sha256(f"{symbol}|{published_at}|{url}".encode()).hexdigest()[:16]
        out.append({
            "source": "finnhub",
            "asset_class": "equity",
            "symbol": symbol,
            "dedup_key": dedup_key,
            "fetched_at": fetched_at,
            **art,  # preserve every field Finnhub gave us
        })
    return out


def write_to_s3(bucket: str, symbol: str, records: list[dict]) -> str:
    if not records:
        LOG.info("No news for %s; skipping write.", symbol)
        return ""
    now = datetime.now(timezone.utc)
    key = (
        f"source=finnhub/asset_class=equity/symbol={symbol}"
        f"/year={now.year:04d}/month={now.month:02d}/day={now.day:02d}"
        f"/hour={now.hour:02d}/data.jsonl"
    )
    body = "\n".join(json.dumps(r) for r in records).encode("utf-8")
    S3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/x-ndjson",
        ServerSideEncryption="aws:kms",
    )
    LOG.info("Wrote %d articles to s3://%s/%s", len(records), bucket, key)
    return key


def lambda_handler(event, context):
    bucket = os.environ["RAW_BUCKET"]
    secret_id = os.environ["SECRET_ID"]
    tickers = os.environ.get("TICKERS", "AAPL,MSFT,NVDA").split(",")
    api_key = get_api_key(secret_id, "FINNHUB_KEY")

    written = []
    for i, symbol in enumerate(tickers):
        if i > 0:
            time.sleep(FINNHUB_REQUEST_INTERVAL_SECONDS)
        symbol = symbol.strip().upper()
        try:
            articles = fetch_news(symbol, api_key)
            records = normalize_news(symbol, articles)
            key = write_to_s3(bucket, symbol, records)
            written.append({"symbol": symbol, "key": key, "records": len(records)})
        except Exception as exc:
            LOG.exception("Failed for %s: %s", symbol, exc)
            written.append({"symbol": symbol, "error": str(exc)})

    return {"written": written, "tickers_attempted": len(tickers)}


if __name__ == "__main__":
    print(json.dumps(lambda_handler({}, None), indent=2))

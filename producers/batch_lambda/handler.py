"""
QuantLake batch fetcher: Alpha Vantage daily bars -> S3 raw zone.

Designed to run as a Lambda OR locally. Locally:

  export RAW_BUCKET=quantlake-raw-<acct>
  export SECRET_ID=quantlake/api-keys/market-data-providers
  export TICKERS=AAPL,MSFT,NVDA
  export AWS_PROFILE=quantlake-admin
  python handler.py

Idempotency contract: each S3 object key embeds (symbol, date), so reruns
overwrite the same key. Each record also carries a dedup_key for downstream
SQL deduplication.
"""

import hashlib
import json
import logging
import os
import time
import urllib.parse
import urllib.request
import urllib.error
from datetime import datetime, timezone

import boto3

# --- module-level boto3 clients ---
# Reused across Lambda warm invocations; cheap on cold start.
SECRETS = boto3.client("secretsmanager")
S3 = boto3.client("s3")

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

AV_BASE = "https://www.alphavantage.co/query"

# Alpha Vantage free tier: 5 req/min. Sleeping 13s between calls keeps us
# safely under it (60 / 5 = 12; we add 1s of safety margin).
AV_REQUEST_INTERVAL_SECONDS = 13


def get_api_key(secret_id: str, key_name: str) -> str:
    """Fetch the JSON secret once and pluck a named field."""
    response = SECRETS.get_secret_value(SecretId=secret_id)
    payload = json.loads(response["SecretString"])
    return payload[key_name]


def fetch_daily_bars(symbol: str, api_key: str) -> dict:
    """
    Call Alpha Vantage TIME_SERIES_DAILY.

    Retries with exponential backoff + jitter on transient failures.
    Returns the parsed JSON dict.
    """
    params = {
        "function": "TIME_SERIES_DAILY",
        "symbol": symbol,
        "outputsize": "compact",  # last 100 trading days
        "apikey": api_key,
    }
    url = f"{AV_BASE}?{urllib.parse.urlencode(params)}"

    max_attempts = 4
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = json.load(resp)
        except urllib.error.HTTPError as e:
            if attempt == max_attempts - 1:
                raise
            sleep_for = (2 ** attempt) + (0.5 * attempt)  # 1s, 2.5s, 4s + jitter
            LOG.warning("HTTP %s on %s, retry %d in %.1fs", e.code, symbol, attempt + 1, sleep_for)
            time.sleep(sleep_for)
            continue

        # Alpha Vantage's special trick: rate limited responses come back HTTP 200
        # with a "Note" or "Information" field instead of "Time Series (Daily)".
        if "Time Series (Daily)" in data:
            return data
        if "Note" in data or "Information" in data:
            sleep_for = 15 + attempt * 5
            LOG.warning("AV rate-limit note for %s: %s -- sleeping %ds",
                        symbol, data.get("Note") or data.get("Information"), sleep_for)
            time.sleep(sleep_for)
            continue
        # Some other malformed payload
        LOG.error("Unexpected AV payload for %s: %s", symbol, json.dumps(data)[:300])
        raise RuntimeError(f"Unexpected AV response for {symbol}")

    raise RuntimeError(f"Exhausted retries for {symbol}")


def normalize_bars(symbol: str, av_payload: dict) -> list[dict]:
    """
    Transform Alpha Vantage's nested format into a flat list of records
    we can stream-write to S3. We do NOT change types here -- raw zone keeps
    upstream representations verbatim. Type cleanup is bronze-layer work.
    """
    series = av_payload["Time Series (Daily)"]
    fetched_at = datetime.now(timezone.utc).isoformat()
    records = []
    for date_str, bar in series.items():
        dedup_key = hashlib.sha256(f"{symbol}|{date_str}".encode()).hexdigest()[:16]
        records.append({
            "source": "alpha_vantage",
            "asset_class": "equity",
            "symbol": symbol,
            "date": date_str,
            "open": bar["1. open"],
            "high": bar["2. high"],
            "low": bar["3. low"],
            "close": bar["4. close"],
            "volume": bar["5. volume"],
            "fetched_at": fetched_at,
            "dedup_key": dedup_key,
        })
    return records


def write_to_s3(bucket: str, symbol: str, records: list[dict]) -> str:
    """
    Write records as newline-delimited JSON (NDJSON) at a Hive-partitioned key:
      source=alpha_vantage/asset_class=equity/symbol=AAPL/year=2026/month=06/day=07/data.jsonl

    NDJSON (one record per line) is the standard raw-zone format because:
    - Athena / Glue read it line-by-line, no schema needed up front
    - Streaming consumers can resume mid-file
    - Compresses well with gzip
    """
    now = datetime.now(timezone.utc)
    key = (
        f"source=alpha_vantage/asset_class=equity/symbol={symbol}"
        f"/year={now.year:04d}/month={now.month:02d}/day={now.day:02d}/data.jsonl"
    )
    body = "\n".join(json.dumps(r) for r in records).encode("utf-8")
    S3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/x-ndjson",
        ServerSideEncryption="aws:kms",  # bucket default would do this too, but explicit is safer
    )
    LOG.info("Wrote %d records to s3://%s/%s", len(records), bucket, key)
    return key


def lambda_handler(event, context):
    """Lambda entry point. Returns a small summary; logs the details."""
    bucket = os.environ["RAW_BUCKET"]
    secret_id = os.environ["SECRET_ID"]
    tickers = os.environ.get("TICKERS", "AAPL,MSFT,NVDA").split(",")

    api_key = get_api_key(secret_id, "ALPHA_VANTAGE_KEY")

    written = []
    for i, symbol in enumerate(tickers):
        if i > 0:
            time.sleep(AV_REQUEST_INTERVAL_SECONDS)
        symbol = symbol.strip().upper()
        try:
            payload = fetch_daily_bars(symbol, api_key)
            records = normalize_bars(symbol, payload)
            key = write_to_s3(bucket, symbol, records)
            written.append({"symbol": symbol, "key": key, "records": len(records)})
        except Exception as exc:
            LOG.exception("Failed for %s: %s", symbol, exc)
            written.append({"symbol": symbol, "error": str(exc)})

    return {"written": written, "tickers_attempted": len(tickers)}


if __name__ == "__main__":
    # Local run path
    print(json.dumps(lambda_handler({}, None), indent=2))

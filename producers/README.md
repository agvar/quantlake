# Producers

Two Python jobs that pull market data from external REST APIs and land it in
the QuantLake `raw` zone as newline-delimited JSON (NDJSON).

## What's here

```
producers/
+-- batch_lambda/        # Alpha Vantage daily bars, runs once/day
|   +-- handler.py
|   +-- requirements.txt
+-- news_lambda/         # Finnhub company-news, runs hourly in market hours
    +-- handler.py
    +-- requirements.txt
```

Both files share the same shape:
1. Fetch API key from Secrets Manager (CMK-encrypted).
2. Pace requests to respect the provider's rate limit.
3. Retry transient failures with exponential backoff + jitter.
4. Normalize each record with `source`, `symbol`, `fetched_at`, `dedup_key`.
5. Write NDJSON to S3 at a Hive-partitioned key, encrypted SSE-KMS.

## Why NDJSON in the raw zone

The raw zone must preserve **upstream representation byte-for-byte** so that
provider bugs and schema drift are debuggable months later. NDJSON keeps the
nested structures intact, doesn't impose a schema, and is line-readable by
Athena, Glue, Spark, jq, and every text editor. Parquet conversion happens in
the *bronze* layer, never in raw.

## Why a `dedup_key` per record

EventBridge Scheduler can double-fire under rare retry conditions. Lambda can
also be invoked twice for the same event in extreme edge cases. We don't try
to prevent these -- we make them *harmless*. Each record carries a
deterministic SHA-256 hash of its natural key, so downstream queries can
`SELECT DISTINCT dedup_key, ...` (or use ROW_NUMBER() OVER ... ORDER BY
fetched_at DESC) to collapse duplicates with no special handling at write time.

## Local development loop

```bash
# Sanity check from your laptop -- skips Lambda packaging entirely.
cd producers/batch_lambda
export RAW_BUCKET=quantlake-raw-<acct>
export SECRET_ID=quantlake/api-keys/market-data-providers
export TICKERS=AAPL,MSFT,NVDA
export AWS_PROFILE=quantlake-admin
pip install boto3   # only if not already installed
python handler.py
```

Then verify the object landed:

```bash
aws s3 ls s3://quantlake-raw-<acct>/source=alpha_vantage/ \
  --recursive --profile quantlake-admin
```

## Packaging for Lambda

The Terraform module `infra/modules/producers/` zips `handler.py` and uploads
it as the Lambda deployment package. boto3 and urllib are baked into the
Python 3.11 Lambda runtime so the zip stays under 10 KB -- cold starts in the
~200 ms range.

## Rate-limit math

- **Alpha Vantage free**: 5 req/min, 500/day. We sleep 13 s between symbols
  (12 s would be the strict limit; 1 s safety margin).
- **Finnhub free**: 60 req/min, ~no daily cap. We sleep 1.1 s between symbols.

If you add more than ~25 symbols to the batch fetcher, you'll start running
into Alpha Vantage's daily 500-call cap (one call per symbol per run, plus a
small number of retries). The right answer at that scale is to switch to
Alpha Vantage's premium tier OR fan out across multiple API keys.

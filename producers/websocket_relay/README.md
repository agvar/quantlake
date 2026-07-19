# Websocket relay (Fargate)

Long-lived Python container that streams Finnhub trade ticks into
`quantlake-market-events`. Runs 24/7 as a Fargate service.

## Behavior

- Fetches Finnhub API key from Secrets Manager on startup.
- Opens one WebSocket, subscribes to each ticker.
- Buffers ticks in memory, publishes to Kinesis every 100 records or 1 second.
- Reconnects with exponential backoff (1s -> 2s -> 4s -> ... capped at 60s).
- On SIGTERM (Fargate stop signal), flushes buffer and exits cleanly.

## Local test

```bash
export SECRET_ID=quantlake/api-keys/market-data-providers
export TICKERS=AAPL,MSFT,NVDA
export KINESIS_STREAM_NAME=quantlake-market-events
export AWS_REGION=us-east-1
export AWS_PROFILE=quantlake-admin

pip install -r requirements.txt
python main.py
```

Ctrl-C stops it. Check Kinesis for records.

## Build + push to ECR

```bash
ACCT=$(aws sts get-caller-identity --query Account --output text --profile quantlake-admin)
REGION=us-east-1

aws ecr get-login-password --region $REGION --profile quantlake-admin \
  | docker login --username AWS --password-stdin ${ACCT}.dkr.ecr.${REGION}.amazonaws.com

docker build -t quantlake-websocket-relay .
docker tag quantlake-websocket-relay:latest \
  ${ACCT}.dkr.ecr.${REGION}.amazonaws.com/quantlake-websocket-relay:latest
docker push ${ACCT}.dkr.ecr.${REGION}.amazonaws.com/quantlake-websocket-relay:latest
```

## Cost when running

- 0.25 vCPU + 0.5 GB Fargate: ~$0.012/hour = **~$8.75/month**
- ECR storage: ~50 MB * $0.10/GB = $0.005/month (negligible)
- CloudWatch logs: ~1 MB/hour * $0.50/GB = ~$0.36/month

Total: ~$9/month if left running 24/7. Rehearsal: stop it between sessions.

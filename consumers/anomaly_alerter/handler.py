"""
Anomaly alerter -- consumes quantlake-anomalies via Kinesis ESM,
deduplicates via DynamoDB conditional PutItem, publishes new anomalies
to an SNS topic.

Environment:
- DEDUP_TABLE       DynamoDB table for dedup state
- ALERT_TOPIC_ARN   SNS topic for new-anomaly notifications
"""

import base64
import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

DDB = boto3.resource("dynamodb")
SNS = boto3.client("sns")

TABLE = DDB.Table(os.environ["DEDUP_TABLE"])
TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]


def is_new(dedup_key: str, anomaly: dict) -> bool:
    """
    Attempt DynamoDB conditional write. Returns True if this dedup_key
    is being seen for the first time (write succeeded), False if it was
    already seen (write refused).

    The condition + PutItem is atomic even under concurrent Lambda invokes.
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    try:
        TABLE.put_item(
            Item={
                "dedup_key": dedup_key,
                "first_seen": now_iso,
                "symbol": anomaly.get("symbol"),
                "event_count": anomaly.get("event_count"),
                "window_start": str(anomaly.get("window_start")),
                # 30-day TTL to auto-clean old dedup entries (see table config).
                "ttl": int(datetime.now(timezone.utc).timestamp()) + 60 * 60 * 24 * 30,
            },
            ConditionExpression="attribute_not_exists(dedup_key)",
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise  # unknown error, propagate


def publish_alert(anomaly: dict) -> None:
    """Send a formatted SNS message."""
    subject = f"[QuantLake] Anomaly: {anomaly.get('symbol')} - {anomaly.get('event_count')} events"
    body = json.dumps(anomaly, default=str, indent=2)
    SNS.publish(TopicArn=TOPIC_ARN, Subject=subject[:99], Message=body)


def lambda_handler(event, context):
    """
    Kinesis ESM invokes with event = {'Records': [{ 'kinesis': {...} }, ...]}
    Each Record's kinesis.data is base64-encoded.
    """
    processed = 0
    alerts_sent = 0

    for rec in event.get("Records", []):
        try:
            raw = base64.b64decode(rec["kinesis"]["data"])
            anomaly = json.loads(raw)
        except Exception as exc:
            LOG.exception("Bad record, skipping: %s", exc)
            continue

        dedup_key = f"{anomaly.get('symbol')}|{anomaly.get('window_start')}"

        if is_new(dedup_key, anomaly):
            publish_alert(anomaly)
            alerts_sent += 1
            LOG.info("Alert sent: %s", dedup_key)
        else:
            LOG.info("Duplicate anomaly, skipped: %s", dedup_key)

        processed += 1

    return {
        "records_processed": processed,
        "alerts_sent": alerts_sent,
        "batch_size": len(event.get("Records", [])),
    }

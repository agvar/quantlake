# Module: producers

Two Lambdas + two EventBridge Schedules + their CloudWatch log groups and an
invoke role.

```
        EventBridge Scheduler                  Secrets Manager
        +--------------------+                 +--------------+
        | batch-daily        |                 | api-keys/    |
        | cron 21:30 UTC     |                 |  market-data |
        +----------+---------+                 +------+-------+
                   |                                  |
                   | scheduler-invoke-role            | GetSecretValue
                   v                                  v
        +----------+---------+   reads      +---------+--------+
        | batch-fetcher      +------------->+ lambda-fetcher-  |
        | Lambda             |   secret     |  role            |
        +----------+---------+              +---------+--------+
                   |                                  |
                   | PutObject (SSE-KMS)              | GenerateDataKey
                   v                                  v
        +----------+---------+              +---------+--------+
        | s3://quantlake-    |   wraps      | alias/quantlake- |
        |  raw-<acct>/...    +<-------------+  lake CMK        |
        +--------------------+              +------------------+
```

The news Lambda is the same shape, different schedule (hourly Mon-Fri 13:00-22:00 UTC).

## Why two separate Lambdas instead of one with branching

Different schedules, different rate limits, different SLAs. The batch fetcher
must finish before the next market day; the news fetcher should be responsive
to breaking news. Splitting them lets us tune memory, timeout, and retries
independently, and one failing doesn't take the other down.

## Why a dedicated scheduler invoke role

EventBridge Scheduler is the *caller* of the Lambda invoke API. The Lambda
execution role is the role assumed *inside* the function. Mixing them is a
common anti-pattern: it makes the Lambda role's blast radius larger than it
needs to be. With a separate role, the scheduler can only do one thing
(invoke these two functions); the Lambda role can only do its data-plane
work (read secrets, write S3).

## The cron syntax gotcha

AWS cron has SIX fields (`min hour day-of-month month day-of-week year`),
not the standard five. Day-of-month and day-of-week are mutually exclusive --
one must be `?` (any). Forgetting this is a top exam-scenario error.

Our schedules:
- `cron(30 21 * * ? *)` -- daily 21:30 UTC, any day-of-week
- `cron(0 13-22 ? * MON-FRI *)` -- hourly 13:00-22:00 UTC, weekdays only

## Manual invoke (sanity check after deploy)

```bash
aws lambda invoke \
  --function-name quantlake-batch-fetcher \
  --profile quantlake-admin \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' \
  /tmp/out.json
cat /tmp/out.json | jq
```

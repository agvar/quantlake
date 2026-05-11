QuantLake is a multi-asset market intelligence platform. It ingests real-time tick data, end-of-day bars, corporate actions, and news/sentiment across equities, FX, and crypto. It builds a point-in-time lakehouse with full ACID and time-travel, computes signals (momentum, volatility regime, volume-spike, sentiment-shock), and surfaces them through dashboards for portfolio managers and through a feature store for downstream quant models. The project is intentionally exam-scoped: every AWS data service in the DEA-C01 blueprint is exercised in proportion to its weight on the exam.

##Architecture

```
yfinance / Polygon.io ─────────► ┌────────────────────────────┐
   WebSocket (real-time ticks)      │  EC2 t4g.nano: WS producer │
                                    │  + Lambda REST fetchers    │
   Alpha Vantage / Finnhub  ──EB───►│                            │
   (EOD bars, fundamentals,         │                            │
    news, sentiment)                └─────────────┬──────────────┘
                                                  │
                                                  ▼
                                       ┌──────────────────┐
                                       │  Kinesis Data    │
                                       │     Streams      │
                                       │  market-events   │
                                       └────────┬─────────┘
                                                │
                          ┌─────────────────────┼─────────────────────┐
                          ▼                     ▼                     ▼
                ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐
                │ Kinesis Firehose │  │ Managed Flink    │  │ Lambda enrich   │
                │  → S3 raw zone   │  │ OHLC windows,    │  │ → DynamoDB      │
                │  Parquet/Snappy  │  │ vol-spike, gap,  │  │ latest_quote    │
                │  partition by    │  │ regime detection │  │ + sector lookup │
                │  symbol, date    │  └────────┬─────────┘  └─────────────────┘
                └─────────┬────────┘           │
                          │                    ▼
                          │           ┌──────────────────┐
                          │           │ SNS alerts +     │
                          │           │ OpenSearch index │
                          │           │ (news + signals) │
                          │           └──────────────────┘
                          ▼
                ┌────────────────────┐    ┌──────────────────┐
                │ Glue ETL (PySpark) │ ─► │ S3 curated zone  │
                │ raw → bronze →     │    │ Iceberg tables   │
                │ silver (Iceberg)   │    │ partitioned by   │
                │ + Glue DQ rules    │    │ symbol, date     │
                └─────────┬──────────┘    └────────┬─────────┘
                          │                        │
                          ▼                        ▼
                ┌────────────────────┐   ┌──────────────────────┐
                │ Glue Data Catalog  │ ◄─┤ Athena queries       │
                │ + Lake Formation   │   │ point-in-time/as-of  │
                │ LF-Tags: AssetCls, │   │ via Iceberg time     │
                │ MNPI, Confidential │   │ travel               │
                └─────────┬──────────┘   └──────────────────────┘
                          ▼
                ┌──────────────────┐
                │ Step Functions   │ ───►┌──────────────────┐
                │ market-open ETL  │     │ Redshift         │
                │ market-close ETL │     │ Serverless gold  │
                │ + EventBridge    │     │ portfolio aggs   │
                │ Scheduler        │     │ sector rollups   │
                └──────────────────┘     │ + Spectrum       │
                          ▲              └──────────┬───────┘
                          │                          │
                ┌──────────────────┐                  ▼
                │ RDS Postgres     │       ┌──────────────────┐
                │ instrument       │ ─DMS─►│   QuickSight     │
                │ reference data   │  CDC  │   PM/quant       │
                │ (tickers,        │       │   dashboards     │
                │  corp actions,   │       └──────────────────┘
                │  sectors)        │
                └──────────────────┘

```
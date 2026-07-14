# Module: glue

Catalog databases + raw tables + first ETL job.

## Databases

- `quantlake_raw` -- points at S3 raw bucket. Tables are external, JSON, unchanged.
- `quantlake_bronze` -- typed + partitioned Parquet. First bronze table
  `finnhub_news` auto-created by the ETL job on first run.
- `quantlake_silver` / `quantlake_gold` -- placeholder databases for Day 9+.

## Why partition projection instead of a crawler

Partition projection tells Athena and Glue "compute the partition list from
these templates at query time" instead of maintaining an actual list of
partitions in the catalog. Wins:
- **Zero crawler cost** -- no scheduled DPU-hours to keep partitions fresh.
- **Zero lag** -- new S3 files are queryable the second they land; no wait
  for the next crawler run.
- **Query pruning still works** -- `WHERE year=2026 AND symbol='AAPL'` still
  reads only that partition, just like real partitions.

Trade-off: you must know the *ranges/enums* up front. For year/month/day/hour
that's easy. For the symbols list we hardcode the current tickers; add more
by extending `var.tickers`.

## Why the Spark script uses DynamicFrame from catalog

Three reasons:
1. **Job bookmarks** track per-file mtime and only work with catalog reads.
2. **Schema tolerance**: raw JSON has occasional missing fields. DynamicFrame
   handles this without crashes; a plain DataFrame `spark.read.json` might.
3. **Consistent catalog view**: the job uses the same table definition
   Athena users see, so bugs in schema evolution are debuggable in one place.

## Cost per bronze job run

G.1X x 2 workers = 2 DPU. Job typically completes in 2-3 min at dev volume:
`2 DPU * 3/60 hr * $0.44/DPU-hr = $0.044`. If run once per day, ~$1.30/month.

## Extending to more raw sources

Copy the `raw_to_bronze_finnhub_news.py` pattern for each source:
1. Add a new PySpark script.
2. Add a new `aws_s3_object` upload.
3. Add a new `aws_glue_job` with different `RAW_TABLE`/`BRONZE_TABLE` args.

The bronze layer accumulates one table per source.

## Common failure modes

| Symptom | Likely cause |
|---|---|
| Job succeeds but bronze table empty | Bookmark advanced past everything; disable bookmark for one run to backfill |
| `TypeError: casting non-numeric to int` | Raw JSON has string where projection expects int (e.g., hour="14a"); tighten upstream Lambda or fix schema |
| `AccessDenied` on script fetch | Glue role missing s3:GetObject on the script bucket/prefix |
| `AccessDenied` on catalog update | Glue role missing glue:CreateTable / UpdateTable (Day 2 grants these on `*`) |
| Bookmarks not advancing | `transformation_ctx` was renamed OR script uses `spark.read.json` instead of catalog read |

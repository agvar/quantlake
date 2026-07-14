# =============================================================================
# 1. Databases -- pure metadata, free
# =============================================================================
resource "aws_glue_catalog_database" "raw" {
  name        = "${var.project}_raw"
  description = "Landing zone tables pointing at the raw S3 bucket. Never mutated in place."
}

resource "aws_glue_catalog_database" "bronze" {
  name        = "${var.project}_bronze"
  description = "Typed + cleaned Parquet, still source-shaped."
}

resource "aws_glue_catalog_database" "silver" {
  name        = "${var.project}_silver"
  description = "Conformed and deduped -- ready for joins."
}

resource "aws_glue_catalog_database" "gold" {
  name        = "${var.project}_gold"
  description = "Business aggregates for BI."
}

# =============================================================================
# 2. Raw tables with partition projection
# =============================================================================

# --- raw finnhub news ---
resource "aws_glue_catalog_table" "raw_finnhub_news" {
  database_name = aws_glue_catalog_database.raw.name
  name          = "finnhub_news"
  description   = "Direct-write Finnhub news JSON. Partitions computed via projection."
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                         = "json"
    "compressionType"                        = "none"
    "projection.enabled"                     = "true"
    "projection.symbol.type"                 = "enum"
    "projection.symbol.values"               = var.tickers
    "projection.year.type"                   = "integer"
    "projection.year.range"                  = "2024,2030"
    "projection.month.type"                  = "integer"
    "projection.month.range"                 = "1,12"
    "projection.month.digits"                = "2"
    "projection.day.type"                    = "integer"
    "projection.day.range"                   = "1,31"
    "projection.day.digits"                  = "2"
    "projection.hour.type"                   = "integer"
    "projection.hour.range"                  = "0,23"
    "projection.hour.digits"                 = "2"
    "storage.location.template"              = "s3://${var.raw_bucket}/source=finnhub/asset_class=equity/symbol=$${symbol}/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
    "EXTERNAL"                               = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket}/source=finnhub/asset_class=equity/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "case.insensitive"       = "TRUE"
        "ignore.malformed.json"  = "TRUE"
      }
    }

    # Columns present in the Finnhub payload (from Day 5 handler.py)
    columns {
      name = "source"
      type = "string"
    }
    columns {
      name = "asset_class"
      type = "string"
    }
    columns {
      name = "dedup_key"
      type = "string"
    }
    columns {
      name = "fetched_at"
      type = "string"
    }
    columns {
      name = "category"
      type = "string"
    }
    columns {
      name = "datetime"
      type = "bigint"
    }
    columns {
      name = "headline"
      type = "string"
    }
    columns {
      name = "id"
      type = "bigint"
    }
    columns {
      name = "image"
      type = "string"
    }
    columns {
      name = "related"
      type = "string"
    }
    columns {
      name = "summary"
      type = "string"
    }
    columns {
      name = "url"
      type = "string"
    }
  }

  # Partition keys -- projection templates fill these at query time
  partition_keys {
    name = "symbol"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
  partition_keys {
    name = "hour"
    type = "int"
  }
}

# --- raw Alpha Vantage bars (no `hour` partition; daily granularity) ---
resource "aws_glue_catalog_table" "raw_alpha_vantage_bars" {
  database_name = aws_glue_catalog_database.raw.name
  name          = "alpha_vantage_bars"
  description   = "Direct-write Alpha Vantage daily bars JSON. Partitions computed via projection."
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                         = "json"
    "projection.enabled"                     = "true"
    "projection.symbol.type"                 = "enum"
    "projection.symbol.values"               = var.tickers
    "projection.year.type"                   = "integer"
    "projection.year.range"                  = "2024,2030"
    "projection.month.type"                  = "integer"
    "projection.month.range"                 = "1,12"
    "projection.month.digits"                = "2"
    "projection.day.type"                    = "integer"
    "projection.day.range"                   = "1,31"
    "projection.day.digits"                  = "2"
    "storage.location.template"              = "s3://${var.raw_bucket}/source=alpha_vantage/asset_class=equity/symbol=$${symbol}/year=$${year}/month=$${month}/day=$${day}/"
    "EXTERNAL"                               = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket}/source=alpha_vantage/asset_class=equity/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "case.insensitive" = "TRUE"
      }
    }

    columns {
      name = "source"
      type = "string"
    }
    columns {
      name = "asset_class"
      type = "string"
    }
    columns {
      name = "symbol"
      type = "string"
    }
    columns {
      name = "date"
      type = "string"
    }
    columns {
      name = "open"
      type = "string"
    }
    columns {
      name = "high"
      type = "string"
    }
    columns {
      name = "low"
      type = "string"
    }
    columns {
      name = "close"
      type = "string"
    }
    columns {
      name = "volume"
      type = "string"
    }
    columns {
      name = "fetched_at"
      type = "string"
    }
    columns {
      name = "dedup_key"
      type = "string"
    }
  }

  partition_keys {
    name = "symbol"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
}

# --- raw Firehose stream-archive (Day 7 output) ---
resource "aws_glue_catalog_table" "raw_stream_archive" {  
  database_name = aws_glue_catalog_database.raw.name
  name          = "stream_archive_news"
  description   = "Firehose GZIP JSON delivery of the market-events stream."
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                         = "json"
    "compressionType"                        = "gzip"
    "projection.enabled"                     = "true"
    "projection.year.type"                   = "integer"
    "projection.year.range"                  = "2024,2030"
    "projection.month.type"                  = "integer"
    "projection.month.range"                 = "1,12"
    "projection.month.digits"                = "2"
    "projection.day.type"                    = "integer"
    "projection.day.range"                   = "1,31"
    "projection.day.digits"                  = "2"
    "projection.hour.type"                   = "integer"
    "projection.hour.range"                  = "0,23"
    "projection.hour.digits"                 = "2"
    "storage.location.template"              = "s3://${var.raw_bucket}/source=stream-archive/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
    "EXTERNAL"                               = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket}/source=stream-archive/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "case.insensitive" = "TRUE"
      }
    }

    columns {
      name = "source"
      type = "string"
    }
    columns {
      name = "asset_class"
      type = "string"
    }
    columns {
      name = "symbol"
      type = "string"
    }
    columns {
      name = "dedup_key"
      type = "string"
    }
    columns {
      name = "headline"
      type = "string"
    }
    columns {
      name = "summary"
      type = "string"
    }
    columns {
      name = "url"
      type = "string"
    }
    columns {
      name = "datetime"
      type = "bigint"
    }
    columns {
      name = "category"
      type = "string"
    }
    columns {
      name = "fetched_at"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
  partition_keys {
    name = "hour"
    type = "int"
  }
}

# =============================================================================
# 3. Upload Spark script to S3 (bronze bucket under _glue-scripts/)
# =============================================================================
resource "aws_s3_object" "raw_to_bronze_script" {
  bucket = var.bronze_bucket
  key    = "_glue_scripts/raw_to_bronze_finnhub_news.py"
  source = "${var.scripts_src_root}/raw_to_bronze_finnhub_news.py"
  etag   = filemd5("${var.scripts_src_root}/raw_to_bronze_finnhub_news.py")
}

# =============================================================================
# 4. Glue ETL job -- raw finnhub -> bronze parquet
# =============================================================================
resource "aws_glue_job" "raw_to_bronze_finnhub" {
  name              = "${var.project}-raw-to-bronze-finnhub-news"
  role_arn          = var.glue_role_arn
  glue_version      = "4.0"        # 4.0 = Spark 3.3, Python 3.10. Current stable.
  worker_type       = var.job_worker_type
  number_of_workers = var.job_num_workers
  timeout           = 30           # minutes; kill if stuck
  max_retries       = 0            # don't retry silently; make failures loud

  command {
    name            = "glueetl"    # "glueetl" = Spark; "pythonshell" = Python-only
    script_location = "s3://${var.bronze_bucket}/${aws_s3_object.raw_to_bronze_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-bookmark-option"          = "job-bookmark-enable"
    "--enable-metrics"               = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"              = "false"   # UI logs eat S3; off for dev
    "--TempDir"                      = "s3://${var.bronze_bucket}/_glue-temp/"
    "--RAW_DATABASE"                 = aws_glue_catalog_database.raw.name
    "--RAW_TABLE"                    = aws_glue_catalog_table.raw_finnhub_news.name
    "--RAW_S3_PATH"                  = "s3://${var.raw_bucket}/source=finnhub/asset_class=equity/"
    "--BRONZE_DATABASE"              = aws_glue_catalog_database.bronze.name
    "--BRONZE_TABLE"                 = "finnhub_news"
    "--BRONZE_S3_PATH"               = "s3://${var.bronze_bucket}/finnhub_news/"
  }

  execution_property {
    max_concurrent_runs = 1   # don't step on our own toes
  }

  tags = { Module = "glue" }
}

# NOTE: Glue does NOT create a per-job CloudWatch log group by default. All
# Glue jobs write to shared groups /aws-glue/jobs/output and /aws-glue/jobs/error
# (auto-created by AWS on first run, no retention control unless you edit them
# in the CloudWatch console). If you want per-job log isolation + retention,
# set the --continuous-log-logGroup default_argument to a name you control
# and pre-create that group with an aws_cloudwatch_log_group resource.
# For dev we accept the shared-groups default -- less isolation, less config.

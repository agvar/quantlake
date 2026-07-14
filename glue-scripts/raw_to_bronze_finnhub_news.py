"""
raw_to_bronze_finnhub_news.py

Reads raw Finnhub news JSON from Glue Data Catalog, cleans + types + dedupes,
writes Parquet to bronze zone and registers/updates the bronze table.

Job parameters (set in Glue job config):
- --RAW_DATABASE            e.g. quantlake_raw
- --RAW_TABLE               e.g. finnhub_news
- --BRONZE_DATABASE         e.g. quantlake_bronze
- --BRONZE_TABLE            e.g. finnhub_news
- --BRONZE_S3_PATH          e.g. s3://quantlake-bronze-<acct>/finnhub_news/
- --RAW_S3_PATH             e.g  s3://quantlake-raw-<acct>/source=finnhub/asset_class=equity/
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType

args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "RAW_DATABASE",       # unused today but kept for future non-projection tables
    "RAW_TABLE",          # ditto
    "RAW_S3_PATH",        # direct S3 read path -- required for projection tables
    "BRONZE_DATABASE",
    "BRONZE_TABLE",
    "BRONZE_S3_PATH",
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# -----------------------------------------------------------------------------
# READ: direct S3 read via from_options.
#
# NOTE: We are NOT using from_catalog() because our raw table uses partition
# projection. Projection is an Athena-only feature -- Glue's catalog reader
# calls GetPartitions, which returns zero partitions on a projection-only
# table, and we read empty. from_options reads S3 paths directly; Spark
# auto-detects Hive-style partition columns from the path (symbol=X/year=Y/...).
#
# Bookmarks still work with from_options + transformation_ctx: they track
# file mtimes, not catalog partitions.
# -----------------------------------------------------------------------------
raw_dyf = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={
        "paths": [args["RAW_S3_PATH"]],
        "recurse": True,
    },
    format="json",
    transformation_ctx="raw_finnhub_source",
)

raw_df = raw_dyf.toDF()

# Glue treats sys.exit() (even sys.exit(0)) as a SYSTEM_EXIT_ERROR. We must
# reach job.commit() through normal control flow. So: if there are no new
# rows, just skip transform+write and fall through to the commit.
if raw_df.rdd.isEmpty():
    print("No new raw rows since last bookmark. Skipping transform + write.")
else:
    # -------------------------------------------------------------------------
    # TRANSFORM: types + cleanup + dedup
    # -------------------------------------------------------------------------
    bronze_df = (
        raw_df
        # Finnhub's `datetime` is a Unix epoch integer (seconds). Cast to timestamp.
        .withColumn("published_at", F.from_unixtime(F.col("datetime").cast("long")).cast("timestamp"))
        # Partition columns derived from published_at.
        .withColumn("event_year",  F.year(F.col("published_at")).cast(IntegerType()))
        .withColumn("event_month", F.month(F.col("published_at")).cast(IntegerType()))
        .withColumn("event_day",   F.dayofmonth(F.col("published_at")).cast(IntegerType()))
        # Provenance
        .withColumn("_ingestion_ts", F.current_timestamp())
        .withColumn("_pipeline", F.lit("raw_to_bronze_finnhub_news"))
        # Dedup using the key we baked in during Day 5.
        .dropDuplicates(["dedup_key"])
        # Final schema -- explicit column selection catches upstream schema drift early.
        .select(
            F.col("symbol").cast("string").alias("symbol"),
            F.col("dedup_key").cast("string").alias("dedup_key"),
            F.col("headline").cast("string").alias("headline"),
            F.col("summary").cast("string").alias("summary"),
            F.col("source").cast("string").alias("news_source"),  # rename to avoid shadowing meta
            F.col("url").cast("string").alias("url"),
            F.col("image").cast("string").alias("image"),
            F.col("category").cast("string").alias("category"),
            F.col("related").cast("string").alias("related"),
            F.col("published_at").cast("timestamp").alias("published_at"),
            F.col("event_year"),
            F.col("event_month"),
            F.col("event_day"),
            F.col("_ingestion_ts").cast("timestamp").alias("_ingestion_ts"),
            F.col("_pipeline").cast("string").alias("_pipeline"),
        )
    )

    # -------------------------------------------------------------------------
    # WRITE: Parquet + auto-register in Data Catalog.
    # UPDATE_IN_DATABASE = if bronze table already exists, update partitions;
    # if not, create it. First run creates; subsequent runs update.
    # -------------------------------------------------------------------------
    bronze_dyf = DynamicFrame.fromDF(bronze_df, glueContext, "bronze_finnhub")

    sink = glueContext.getSink(
        path=args["BRONZE_S3_PATH"],
        connection_type="s3",
        updateBehavior="UPDATE_IN_DATABASE",
        partitionKeys=["symbol", "event_year", "event_month", "event_day"],
        enableUpdateCatalog=True,
        transformation_ctx="bronze_finnhub_sink",
    )
    sink.setCatalogInfo(
        catalogDatabase=args["BRONZE_DATABASE"],
        catalogTableName=args["BRONZE_TABLE"],
    )
    sink.setFormat("glueparquet", compression="snappy")
    sink.writeFrame(bronze_dyf)

# Always commit -- advances bookmark either way (past processed files).
job.commit()

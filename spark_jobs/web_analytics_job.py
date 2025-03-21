from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

BUCKET_NAME = "dataplatfrom-demo-bucket"

def analyze_web_logs(parquet_path, s3_output_path):
    """
    Analyzes web log data from a Parquet file and writes metrics to S3.

    Args:
        parquet_path (str): The path to the Parquet file containing web log data in S3.
        s3_output_path (str): The S3 path to write the output metrics.
    """

    spark = SparkSession.builder \
        .appName("WebLogAnalysisS3") \
        .config("spark.hadoop.fs.s3a.endpoint", "s3.amazonaws.com") \
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
        .getOrCreate()

    try:
        df = spark.read.parquet(parquet_path)

        # Convert bigint to timestamp
        df = df.withColumn("timestamp", (F.col("timestamp") / 1000).cast("timestamp"))

        # Extract device type from user agent (simplified)
        def extract_device(user_agent):
            if "Mobile" in user_agent or "Android" in user_agent or "iPhone" in user_agent:
                return "Mobile"
            elif "iPad" in user_agent:
                return "Tablet"
            else:
                return "Desktop" #Default if no mobile or tablet indicator.

        extract_device_udf = F.udf(extract_device)

        df = df.withColumn("device", extract_device_udf("user_agent"))

        # Daily Analysis
        daily_df = df.withColumn("date", F.to_date("timestamp"))

        # Top 5 IP addresses (daily)
        top_ips_daily = (
            daily_df.groupBy("date", "ip")
            .agg(F.count("*").alias("request_count"))
            .withColumn("rank", F.rank().over(Window.partitionBy("date").orderBy(F.desc("request_count"))))
            .filter(F.col("rank") <= 5)
            .orderBy("date", "rank")
        )

        # Top 5 devices (daily)
        top_devices_daily = (
            daily_df.groupBy("date", "device")
            .agg(F.count("*").alias("request_count"))
            .withColumn("rank", F.rank().over(Window.partitionBy("date").orderBy(F.desc("request_count"))))
            .filter(F.col("rank") <= 5)
            .orderBy("date", "rank")
        )

        # Weekly Analysis
        weekly_df = df.withColumn("week_start", F.date_trunc("week", "timestamp"))

        # Top 5 IP addresses (weekly)
        top_ips_weekly = (
            weekly_df.groupBy("week_start", "ip")
            .agg(F.count("*").alias("request_count"))
            .withColumn("rank", F.rank().over(Window.partitionBy("week_start").orderBy(F.desc("request_count"))))
            .filter(F.col("rank") <= 5)
            .orderBy("week_start", "rank")
        )

        # Top 5 devices (weekly)
        top_devices_weekly = (
            weekly_df.groupBy("week_start", "device")
            .agg(F.count("*").alias("request_count"))
            .withColumn("rank", F.rank().over(Window.partitionBy("week_start").orderBy(F.desc("request_count"))))
            .filter(F.col("rank") <= 5)
            .orderBy("week_start", "rank")
        )

        # Write results to S3
        top_ips_daily.write.mode("overwrite").parquet(f"{s3_output_path}/top_ips_daily")
        top_devices_daily.write.mode("overwrite").parquet(f"{s3_output_path}/top_devices_daily")
        top_ips_weekly.write.mode("overwrite").parquet(f"{s3_output_path}/top_ips_weekly")
        top_devices_weekly.write.mode("overwrite").parquet(f"{s3_output_path}/top_devices_weekly")

        print(f"Metrics written to {s3_output_path}")

    except Exception as e:
        print(f"An error occurred: {e}")

    finally:
        spark.stop()

if __name__ == "__main__":
    parquet_file_path = f"s3a://{BUCKET_NAME}/raw/web_logs/web_log_data.parquet"
    s3_output_path = f"s3a://{BUCKET_NAME}/analytics/web_logs"
    analyze_web_logs(parquet_file_path, s3_output_path)
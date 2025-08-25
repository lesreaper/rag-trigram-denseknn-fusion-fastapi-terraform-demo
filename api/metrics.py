import boto3
from datetime import datetime
from config import AWS_REGION

cloudwatch = boto3.client("cloudwatch", region_name=AWS_REGION)

def push_ingest_metric(status: str):
    try:
        cloudwatch.put_metric_data(
            Namespace="RAGDemo/Ingestion",
            MetricData=[{
                "MetricName": "IngestionCount",
                "Dimensions": [{"Name": "Status", "Value": status}],
                "Timestamp": datetime.utcnow(),
                "Value": 1,
                "Unit": "Count"
            }]
        )
    except Exception as e:
        print(f"[WARN] CloudWatch metric failed: {e}")

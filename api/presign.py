import os, uuid
import boto3
from botocore.client import Config
from fastapi import APIRouter, HTTPException, Query
from botocore.exceptions import NoCredentialsError, ClientError

router = APIRouter()
REGION = os.getenv("AWS_REGION", "us-east-1")
BUCKET = os.getenv("RAW_BUCKET")

def _content_type(ext: str) -> str:
    return {"csv": "text/csv", "zip": "application/zip"}.get(ext.lower(), "application/octet-stream")

@router.get("/ingest/presign")
def presign_upload(ext: str = Query("csv")):
    if not BUCKET:
        raise HTTPException(500, "RAW_BUCKET not configured")
    try:
        # 👇 Force SigV4 so URLs look like X-Amz-… instead of AWSAccessKeyId/Signature
        s3 = boto3.client("s3", region_name=REGION, config=Config(signature_version="s3v4"))
        key = f"uploads/{uuid.uuid4().hex}.{ext.lower()}"

        put_url = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={"Bucket": BUCKET, "Key": key, "ContentType": _content_type(ext)},
            ExpiresIn=3600,
        )
        get_url = s3.generate_presigned_url(
            ClientMethod="get_object",
            Params={"Bucket": BUCKET, "Key": key},
            ExpiresIn=3600,
        )
        return {"bucket": BUCKET, "key": key, "put_url": put_url, "get_url": get_url}
    except NoCredentialsError:
        raise HTTPException(
            500,
            "AWS credentials not found. Mount ~/.aws and set AWS_PROFILE + AWS_SDK_LOAD_CONFIG=1, "
            "or pass env creds / use a task role."
        )
    except ClientError as e:
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise HTTPException(500, f"Failed to presign: {msg}")

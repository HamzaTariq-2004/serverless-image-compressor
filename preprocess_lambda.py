import json
import boto3
import os
import uuid
from botocore.exceptions import ClientError

UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]
REGION = os.environ["UPLOAD_BUCKET_REGION"]

# Initialize S3 client with region
s3 = boto3.client("s3", region_name=REGION)

def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        email = body.get("email")
        quality = body.get("quality")
        file_type = body.get("fileType", "image/jpeg").lower()

        if not email or not quality:
            return {
                "statusCode": 400,
                "headers": {
                    "Access-Control-Allow-Origin": "*",
                    "Content-Type": "application/json"
                },
                "body": json.dumps({"message": "Missing email or quality selection"})
            }

        mime_map = {
            "image/jpeg": "jpg",
            "image/jpg": "jpg",
            "image/png": "png"
        }

        if file_type not in mime_map:
            return {
                "statusCode": 400,
                "headers": {
                    "Access-Control-Allow-Origin": "*",
                    "Content-Type": "application/json"
                },
                "body": json.dumps({"message": f"Unsupported file type: {file_type}"})
            }

        ext = mime_map[file_type]
        image_key = f"{uuid.uuid4()}.{ext}"

        presigned_post = s3.generate_presigned_post(
            Bucket=UPLOAD_BUCKET,
            Key=image_key,
            Fields={
                "Content-Type": file_type,
                "x-amz-meta-email": email,
                "x-amz-meta-quality": str(quality),
                "x-amz-meta-original-filename": body.get("fileName", "unknown")
            },
            Conditions=[
                {"Content-Type": file_type},
                ["starts-with", "$x-amz-meta-email", ""],
                ["starts-with", "$x-amz-meta-quality", ""],
                ["starts-with", "$x-amz-meta-original-filename", ""],
                ["content-length-range", 1, 10485760]
            ],
            ExpiresIn=300
        )

        # FIX: Use regional S3 URL to avoid 307 redirect
        regional_url = f"https://{UPLOAD_BUCKET}.s3.{REGION}.amazonaws.com"

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "uploadUrl": regional_url,  # Changed from presigned_post["url"]
                "fields": presigned_post["fields"],
                "key": image_key
            })
        }

    except ClientError as e:
        print(f"ClientError: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json"
            },
            "body": json.dumps({"message": str(e)})
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json"
            },
            "body": json.dumps({"message": "Internal server error"})
        }
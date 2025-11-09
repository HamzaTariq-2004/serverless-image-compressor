import boto3
import os
import json
import tempfile
import urllib.request
import time
from PIL import Image

s3 = boto3.client("s3", region_name="ap-south-1")

UPLOAD_BUCKET = os.environ.get("UPLOAD_BUCKET")
COMPRESSED_BUCKET = os.environ.get("COMPRESSED_BUCKET")
SENDER_EMAIL = os.environ.get("SENDER_EMAIL")
SENDGRID_API_KEY = os.environ.get("SENDGRID_API_KEY")

def lambda_handler(event, context):
    start_time = time.time()
    print(f"[INFO] Lambda invoked - Request ID: {context.aws_request_id}")  # FIXED
    print(f"[INFO] Received event: {json.dumps(event)}")
    
    try:
        for record in event["Records"]:
            message_body = json.loads(record["body"])
            
            # Skip S3 test events
            if message_body.get("Event") == "s3:TestEvent":
                print("[INFO] Skipping S3 test event")
                continue
            
            if "Records" not in message_body:
                print(f"[WARN] Invalid message format: {message_body}")
                continue
                
            s3_record = message_body["Records"][0]
            bucket = s3_record["s3"]["bucket"]["name"]
            key = s3_record["s3"]["object"]["key"]
            file_size = s3_record["s3"]["object"].get("size", 0)
            
            print(f"[INFO] Processing image - Bucket: {bucket}, Key: {key}, Size: {file_size} bytes")

            # Get metadata
            head = s3.head_object(Bucket=bucket, Key=key)
            metadata = head.get("Metadata", {})
            
            email = metadata.get("email")
            quality = metadata.get("quality", "60")
            
            print(f"[INFO] Metadata - Email: {email}, Quality: {quality}")

            if not email:
                print("[WARN] No email found in metadata, skipping email notification")
                continue

            try:
                compression = int(quality)
            except:
                compression = 60
                print(f"[WARN] Invalid quality value, using default: {compression}")

            # Download and compress
            download_start = time.time()
            with tempfile.NamedTemporaryFile(suffix=".tmp") as temp_in:
                s3.download_file(bucket, key, temp_in.name)
                download_time = time.time() - download_start
                print(f"[METRIC] Download time: {download_time:.2f}s")
                
                img = Image.open(temp_in.name)
                original_size = os.path.getsize(temp_in.name)
                
                file_ext = key.split(".")[-1].lower()
                img_format = "JPEG" if file_ext in ["jpg", "jpeg"] else "PNG"
                compressed_key = key.rsplit(".", 1)[0] + f"_compressed.{file_ext}"

                # Compress
                compress_start = time.time()
                with tempfile.NamedTemporaryFile(suffix=f".{file_ext}") as temp_out:
                    if img_format == "JPEG":
                        img = img.convert("RGB")
                        img.save(temp_out.name, format=img_format, quality=compression, optimize=True)
                    else:
                        img.save(temp_out.name, format=img_format, optimize=True, compress_level=9)

                    compressed_size = os.path.getsize(temp_out.name)
                    compress_time = time.time() - compress_start
                    compression_ratio = (1 - compressed_size/original_size) * 100
                    
                    print(f"[METRIC] Compression time: {compress_time:.2f}s")
                    print(f"[METRIC] Original size: {original_size} bytes")
                    print(f"[METRIC] Compressed size: {compressed_size} bytes")
                    print(f"[METRIC] Compression ratio: {compression_ratio:.1f}%")

                    # Upload
                    upload_start = time.time()
                    s3.upload_file(
                        temp_out.name,
                        COMPRESSED_BUCKET,
                        compressed_key,
                        ExtraArgs={"ContentType": f"image/{file_ext}"}
                    )
                    upload_time = time.time() - upload_start
                    print(f"[METRIC] Upload time: {upload_time:.2f}s")
                    print(f"[SUCCESS] Uploaded compressed image: {compressed_key}")

            # Generate URL
            compressed_url = f"https://{COMPRESSED_BUCKET}.s3.ap-south-1.amazonaws.com/{compressed_key}"

            # Send email
            email_start = time.time()
            send_email_sendgrid(email, compressed_url, key)
            email_time = time.time() - email_start
            print(f"[METRIC] Email send time: {email_time:.2f}s")
            print(f"[SUCCESS] Email sent successfully to: {email}")

        total_time = time.time() - start_time
        print(f"[METRIC] Total processing time: {total_time:.2f}s")
        print(f"[INFO] Lambda execution completed successfully")
        
        return {"statusCode": 200, "body": "Processed successfully"}

    except Exception as e:
        print(f"[ERROR] Lambda execution failed: {str(e)}")
        import traceback
        traceback.print_exc()
        raise e

def send_email_sendgrid(recipient, file_url, original_filename):
    data = {
        "personalizations": [{
            "to": [{"email": recipient}],
            "subject": "Your Compressed Image is Ready! 🎉"
        }],
        "from": {"email": SENDER_EMAIL, "name": "Image Compressor"},
        "content": [{
            "type": "text/html",
            "value": f"""
            <html>
            <body style="font-family: Arial, sans-serif; padding: 20px; background-color: #f5f5f5;">
                <div style="max-width: 600px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
                    <h2 style="color: #4CAF50; margin-bottom: 20px;">✓ Image Compression Complete!</h2>
                    <p style="font-size: 16px; color: #333; line-height: 1.6;">
                        Your image <strong>{original_filename}</strong> has been successfully compressed and is ready for download.
                    </p>
                    <div style="text-align: center; margin: 30px 0;">
                        <a href="{file_url}" style="background-color: #4CAF50; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-size: 16px; display: inline-block;">
                            📥 Download Compressed Image
                        </a>
                    </div>
                    <p style="font-size: 14px; color: #666;">
                        <strong>Note:</strong> This link will be available for 7 days.
                    </p>
                    <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">
                    <p style="font-size: 12px; color: #999; text-align: center;">
                        Powered by <strong>AWS Serverless Image Compressor</strong><br>
                        Developed by <strong>Hamza Tariq</strong>
                    </p>
                </div>
            </body>
            </html>
            """
        }]
    }
    
    req = urllib.request.Request(
        "https://api.sendgrid.com/v3/mail/send",
        data=json.dumps(data).encode('utf-8'),
        headers={
            "Authorization": f"Bearer {SENDGRID_API_KEY}",
            "Content-Type": "application/json"
        },
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            print(f"SendGrid response: {response.status}")
            if response.status == 202:
                print("Email queued successfully by SendGrid!")
            else:
                print(f"Unexpected status: {response.status}")
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"SendGrid HTTP error: {e.code} - {error_body}")
        raise e
    except Exception as e:
        print(f"SendGrid request error: {e}")
        raise e
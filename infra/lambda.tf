resource "aws_lambda_function" "preprocess" {
  function_name = "preprocess_lambda"
  filename      = "../preprocess_lambda.zip"
  handler       = "preprocess_lambda.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      UPLOAD_BUCKET = aws_s3_bucket.upload.bucket
      UPLOAD_BUCKET_REGION = "ap-south-1"
    }
  }
}

resource "aws_lambda_function" "worker" {
  function_name = "worker_lambda"
  filename      = "../worker_lambda.zip"
  handler       = "worker_lambda.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 450
  memory_size   = 1536
  layers        = [aws_lambda_layer_version.pillow_layer.arn]
  environment {
    variables = {
      UPLOAD_BUCKET     = aws_s3_bucket.upload.bucket
      COMPRESSED_BUCKET = aws_s3_bucket.compressed.bucket
      SENDER_EMAIL      = "hamza4happiness@gmail.com"  
      SENDGRID_API_KEY  = "API_KEY"   # Replace it with your API key
    }
  }
}

resource "aws_lambda_layer_version" "pillow_layer" {
  filename            = "../layer/pillow-layer.zip"
  layer_name          = "pillow-layer"
  compatible_runtimes = ["python3.12"]
}

# Grant the SQS queue permission to invoke worker (via event source mapping)
resource "aws_lambda_event_source_mapping" "worker_sqs" {
  event_source_arn = aws_sqs_queue.image_queue.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 1
  enabled          = true
}

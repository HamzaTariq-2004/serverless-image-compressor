# --- Upload bucket ---
resource "aws_s3_bucket" "upload" {
  bucket         = var.upload_bucket_name
  force_destroy  = true
}

resource "aws_s3_bucket_notification" "upload_notification" {
  bucket = aws_s3_bucket.upload.id

  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".jpg"
  }

  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".png"
  }

  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".jpeg"
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}

resource "aws_s3_bucket_ownership_controls" "upload_ownership" {
  bucket = aws_s3_bucket.upload.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
  depends_on = [aws_s3_bucket.upload]
}

resource "aws_s3_bucket_cors_configuration" "upload_cors" {
  bucket = aws_s3_bucket.upload.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    allowed_origins = ["*"]  # Changed to wildcard for testing
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# --- Compressed bucket ---
resource "aws_s3_bucket" "compressed" {
  bucket        = var.compressed_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "compressed_ownership" {
  bucket = aws_s3_bucket.compressed.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
  depends_on = [aws_s3_bucket.compressed]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "compressed_enc" {
  bucket = aws_s3_bucket.compressed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
  depends_on = [aws_s3_bucket.compressed]
}

# --- Frontend bucket ---
resource "aws_s3_bucket" "frontend" {
  bucket        = var.frontend_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "frontend_ownership" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
  depends_on = [aws_s3_bucket.frontend]
}

resource "aws_s3_bucket_website_configuration" "frontend_site" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
  depends_on = [aws_s3_bucket.frontend]
}

# --- Policies ---
resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowCloudFrontReadViaDistributionArn"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend_cdn.arn
          }
        }
      }
    ]
  })
  depends_on = [aws_cloudfront_distribution.frontend_cdn]
}

resource "aws_s3_bucket_policy" "upload_policy" {
  bucket = aws_s3_bucket.upload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowLambdaPresignedUpload"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${aws_s3_bucket.upload.arn}/*"
      }
    ]
  })
  depends_on = [aws_iam_role.lambda_role, aws_s3_bucket.upload]
}

# Add a separate policy for the compressed bucket
resource "aws_s3_bucket_policy" "compressed_policy" {
  bucket = aws_s3_bucket.compressed.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowLambdaReadWriteCompressedBucket"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.compressed.arn}/*"
      },
      {
        Sid = "AllowPublicRead"
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.compressed.arn}/*"
      }
    ]
  })
  depends_on = [aws_iam_role.lambda_role, aws_s3_bucket.compressed]
}

resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.frontend.id
  key = "index.html"
  source = "../index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "style" {
  bucket = aws_s3_bucket.frontend.id
  key = "style.css"
  source = "../style.css"
  content_type = "text/css"
}

resource "aws_s3_object" "script" {
  bucket = aws_s3_bucket.frontend.id
  key = "script.js"
  source = "../script.js"
  content_type = "application/javascript"
}
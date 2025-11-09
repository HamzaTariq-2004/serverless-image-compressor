resource "aws_sqs_queue" "image_queue" {
  name                       = "image-compress-queue-${random_id.suffix.hex}"
  visibility_timeout_seconds = 500 # must by > than lambda timeout 
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  redrive_policy = jsonencode({
    maxReceiveCount     = 5,
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
  })
}

resource "aws_sqs_queue" "dlq" {
  name                      = "image-compress-dlq-${random_id.suffix.hex}"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.image_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.image_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.upload.arn
          }
        }
      }
    ]
  })
}
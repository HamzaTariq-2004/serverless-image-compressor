output "api_endpoint" {
  value = aws_apigatewayv2_api.presigned_api.api_endpoint
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.frontend_cdn.domain_name
}

output "upload_bucket" {
  value = aws_s3_bucket.upload.bucket
}

output "queue_url" {
  value = aws_sqs_queue.image_queue.id
}

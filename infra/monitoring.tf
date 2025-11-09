# CloudWatch Log Groups with Retention
resource "aws_cloudwatch_log_group" "preprocess_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.preprocess.function_name}"
  retention_in_days = 3  # Keep logs for 2 days (cost optimization)
}

resource "aws_cloudwatch_log_group" "worker_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.worker.function_name}"
  retention_in_days = 3
}

# CloudWatch Alarms - Get notified on issues

# Lambda Error Alarm - Worker
resource "aws_cloudwatch_metric_alarm" "worker_lambda_errors" {
  alarm_name          = "worker-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 5  # Alert if more than 5 errors in 5 min
  alarm_description   = "Worker Lambda is experiencing errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.worker.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Lambda Error Alarm - Preprocess
resource "aws_cloudwatch_metric_alarm" "preprocess_lambda_errors" {
  alarm_name          = "preprocess-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Preprocess Lambda is experiencing errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.preprocess.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Lambda Duration Alarm - Check for timeouts
resource "aws_cloudwatch_metric_alarm" "worker_lambda_duration" {
  alarm_name          = "worker-lambda-high-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 400000  # 400 seconds (close to 450s timeout)
  alarm_description   = "Worker Lambda is taking too long"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.worker.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# SQS Dead Letter Queue Alarm
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "sqs-dlq-has-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 0  # Alert on ANY message in DLQ
  alarm_description   = "Messages in Dead Letter Queue - investigate failures"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# SQS Main Queue - Check for message buildup
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "sqs-queue-high-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100  # More than 100 messages waiting
  alarm_description   = "SQS queue has too many messages - Lambda might be slow"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.image_queue.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# API Gateway 5xx Errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "api-gateway-server-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "API Gateway returning 5xx errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.presigned_api.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# API Gateway 4xx Errors (client errors - might indicate issues)
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx" {
  alarm_name          = "api-gateway-client-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 20  # High threshold - some 4xx are expected
  alarm_description   = "API Gateway returning many 4xx errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.presigned_api.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "image-compressor-alerts"
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "hamza4happiness@gmail.com"  # email for alerts
}

# CloudWatch Dashboard

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "image-compressor-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Lambda Invocations
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Preprocess" }],
            [".", ".", { stat = "Sum", label = "Worker" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-south-1"
          title   = "Lambda Invocations"
          period  = 300
        }
      },
      # Lambda Errors
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", { stat = "Sum", label = "Preprocess Errors" }],
            [".", ".", { stat = "Sum", label = "Worker Errors" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-south-1"
          title   = "Lambda Errors"
          period  = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Lambda Duration
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { stat = "Average", label = "Preprocess Avg Duration" }],
            ["...", { stat = "Maximum", label = "Preprocess Max Duration" }],
            [".", ".", { stat = "Average", label = "Worker Avg Duration" }],
            ["...", { stat = "Maximum", label = "Worker Max Duration" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-south-1"
          title   = "Lambda Duration (ms)"
          period  = 300
        }
      },
      # SQS Queue Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", { stat = "Average", label = "Messages in Queue" }],
            [".", "NumberOfMessagesSent", { stat = "Sum", label = "Messages Sent" }],
            [".", "NumberOfMessagesReceived", { stat = "Sum", label = "Messages Received" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-south-1"
          title   = "SQS Queue Metrics"
          period  = 300
        }
      },
      # API Gateway Requests
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum", label = "Total Requests" }],
            [".", "4XXError", { stat = "Sum", label = "4xx Errors" }],
            [".", "5XXError", { stat = "Sum", label = "5xx Errors" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-south-1"
          title   = "API Gateway Requests"
          period  = 300
        }
      },
      # API Latency
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Latency", { stat = "Average", label = "Avg Latency" }],
            ["...", { stat = "Maximum", label = "Max Latency" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-south-1"
          title   = "API Gateway Latency (ms)"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch Insights Query Definitions

resource "aws_cloudwatch_query_definition" "lambda_errors" {
  name = "Lambda Errors - Last Hour"

  log_group_names = [
    aws_cloudwatch_log_group.preprocess_lambda.name,
    aws_cloudwatch_log_group.worker_lambda.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /ERROR/
    | sort @timestamp desc
    | limit 100
  QUERY
}

resource "aws_cloudwatch_query_definition" "lambda_duration" {
  name = "Lambda Duration Analysis"

  log_group_names = [
    aws_cloudwatch_log_group.worker_lambda.name
  ]

  query_string = <<-QUERY
    filter @type = "REPORT"
    | stats avg(@duration), max(@duration), min(@duration) by bin(5m)
  QUERY
}

resource "aws_cloudwatch_query_definition" "successful_uploads" {
  name = "Successful Image Processing"

  log_group_names = [
    aws_cloudwatch_log_group.worker_lambda.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /Email sent successfully/
    | sort @timestamp desc
    | limit 50
  QUERY
}
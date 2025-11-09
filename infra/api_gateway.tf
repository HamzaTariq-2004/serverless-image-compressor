resource "aws_apigatewayv2_api" "presigned_api" {
  name          = "presigned-api"
  protocol_type = "HTTP"

   cors_configuration {
    allow_headers = ["Content-Type", "Authorization", "x-amz-meta-email", "x-amz-meta-quality"]
    allow_origins = ["*"]                      
    allow_methods = ["POST", "OPTIONS"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "preprocess_integration" {
  api_id                 = aws_apigatewayv2_api.presigned_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.preprocess.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "presigned_route" {
  api_id    = aws_apigatewayv2_api.presigned_api.id
  route_key = "POST /get-presigned-url"
  target    = "integrations/${aws_apigatewayv2_integration.preprocess_integration.id}"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.preprocess.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.presigned_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.presigned_api.id
  name        = "$default"
  auto_deploy = true
}
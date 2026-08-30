resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${local.name_prefix}-ingest"
  retention_in_days = 7
}

locals {
  lambda_env = {
    NODE_ENV                    = "production"
    GNOSHBOT_ENV                = "production"
    DATABASE_URL                = aws_ssm_parameter.database_url.value
    SKIP_LOG_HMAC_SECRET        = aws_ssm_parameter.skip_log_hmac.value
    MENU_WRAP_KEY_HEX           = aws_ssm_parameter.menu_wrap.value
    OVERTURE_RELEASE            = var.overture_release
    INGEST_LAMBDA_FUNCTION_NAME = "${local.name_prefix}-ingest"
  }
}

resource "aws_lambda_function" "api" {
  function_name = "${local.name_prefix}-api"
  role          = aws_iam_role.api.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.backend.repository_url}:${var.image_tag}"
  architectures = ["x86_64"]
  timeout       = 30
  memory_size   = 512
  # On-demand only. Do not add provisioned_concurrency_config (not on the Siri path).

  image_config {
    command = ["bun", "run", "src/lambda-http.ts"]
  }

  environment {
    variables = local.lambda_env
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  depends_on = [aws_lambda_function.ingest]
}

resource "aws_lambda_function" "ingest" {
  function_name = "${local.name_prefix}-ingest"
  role          = aws_iam_role.ingest.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.backend.repository_url}:${var.image_tag}"
  architectures = ["x86_64"]
  timeout       = 900
  memory_size   = 2048

  ephemeral_storage {
    size = 1024
  }

  image_config {
    command = ["bun", "run", "src/ingest/worker.ts"]
  }

  environment {
    variables = {
      NODE_ENV             = "production"
      GNOSHBOT_ENV         = "production"
      DATABASE_URL         = aws_ssm_parameter.database_url.value
      SKIP_LOG_HMAC_SECRET = aws_ssm_parameter.skip_log_hmac.value
      MENU_WRAP_KEY_HEX    = aws_ssm_parameter.menu_wrap.value
      OVERTURE_RELEASE     = var.overture_release
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.ingest.name
  }
}

resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  cors {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
    max_age       = 86400
  }
}

resource "aws_cloudwatch_metric_alarm" "ingest_duration" {
  alarm_name          = "${local.name_prefix}-ingest-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = 600000
  treat_missing_data  = "notBreaching"
  alarm_description   = "Ingest Lambda exceeded 600s (ceiling is 900s). Bbox jobs only; never scan the theme."

  dimensions = {
    FunctionName = aws_lambda_function.ingest.function_name
  }

  alarm_actions = var.notification_email == "" ? [] : [aws_sns_topic.ops[0].arn]
}

resource "aws_sns_topic" "ops" {
  count = var.notification_email == "" ? 0 : 1
  name  = "${local.name_prefix}-ops"
}

resource "aws_sns_topic_subscription" "ops_email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.ops[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

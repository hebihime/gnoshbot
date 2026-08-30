resource "aws_cloudwatch_event_rule" "purge" {
  name                = "${local.name_prefix}-purge"
  description         = "Nightly purge_stale_unsupported_pois (us-west-2 quiet hours)."
  schedule_expression = "cron(0 9 * * ? *)"
}

resource "aws_cloudwatch_event_target" "purge" {
  rule  = aws_cloudwatch_event_rule.purge.name
  arn   = aws_lambda_function.ingest.arn
  input = jsonencode({ action = "purge" })
}

resource "aws_lambda_permission" "purge" {
  statement_id  = "AllowEventBridgePurge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.purge.arn
}

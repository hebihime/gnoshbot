output "region" {
  description = "Pinned AWS region for all Gnoshbot compute."
  value       = local.region
}

output "environment" {
  description = "Terraform workspace (staging | prod). default is treated as staging."
  value       = local.environment
}

output "overture_bucket" {
  description = "Overture GeoParquet catalog. Anonymous list; GET request charges apply; transfer $0 in-region."
  value       = local.overture_bucket
}

output "api_function_url" {
  description = "Control-plane Lambda Function URL. iOS / backend agent: this is the public HTTPS origin (no ALB)."
  value       = aws_lambda_function_url.api.function_url
}

output "api_function_name" {
  value = aws_lambda_function.api.function_name
}

output "ingest_function_name" {
  description = "Set INGEST_LAMBDA_FUNCTION_NAME on the API Lambda to this value."
  value       = aws_lambda_function.ingest.function_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ssm_prefix" {
  description = "SSM Standard parameters: DATABASE_URL, SKIP_LOG_HMAC_SECRET, MENU_WRAP_KEY_HEX, OVERTURE_RELEASE."
  value       = local.ssm_prefix
}

output "neon_region" {
  value = local.neon_region
}

output "cheap_shape" {
  value = "Neon aws-us-west-2 + two Lambdas (Function URL API, container ingest). No NAT, ALB, RDS, SQS, or provisioned concurrency."
}
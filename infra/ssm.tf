resource "random_password" "skip_hmac" {
  length  = 48
  special = false
}

resource "random_bytes" "menu_wrap" {
  length = 32
}

resource "aws_ssm_parameter" "database_url" {
  name        = "${local.ssm_prefix}/DATABASE_URL"
  description = "Neon pooled Postgres+PostGIS (aws-us-west-2). Standard tier, not Secrets Manager."
  type        = "SecureString"
  tier        = "Standard"
  value       = local.database_url

  lifecycle {
    precondition {
      condition     = local.database_url != ""
      error_message = "Set manage_neon=true or neon_pooled_database_url."
    }
  }
}

resource "aws_ssm_parameter" "skip_log_hmac" {
  name        = "${local.ssm_prefix}/SKIP_LOG_HMAC_SECRET"
  description = "Skip-log HMAC. Rotate independently of MENU_WRAP_KEY_HEX."
  type        = "SecureString"
  tier        = "Standard"
  value       = local.skip_log_hmac_secret
}

resource "aws_ssm_parameter" "menu_wrap" {
  name        = "${local.ssm_prefix}/MENU_WRAP_KEY_HEX"
  description = "AES-GCM wrap key, 32-byte hex."
  type        = "SecureString"
  tier        = "Standard"
  value       = local.menu_wrap_key_hex
}

resource "aws_ssm_parameter" "overture_release" {
  name        = "${local.ssm_prefix}/OVERTURE_RELEASE"
  description = "Pinned Overture release. Not a secret; Standard String."
  type        = "String"
  tier        = "Standard"
  value       = var.overture_release
}

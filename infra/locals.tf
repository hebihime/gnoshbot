# Region pin for all Gnoshbot AWS. GROK.md T01/T04, SCALABILITY.md S1, ARCHITECTURE.md §10.
# Overture catalog is s3://overturemaps-us-west-2; same-region GET is $0 transfer (GET request charges still apply).

locals {
  region          = "us-west-2"
  neon_region     = "aws-us-west-2"
  overture_bucket = "overturemaps-us-west-2"
  overture_prefix = "release/*"
  environments    = ["gnoshbot-staging", "gnoshbot-prod"]
  environment     = terraform.workspace == "default" ? "staging" : terraform.workspace
  name_prefix     = "gnoshbot-${local.environment}"
  ssm_prefix      = "/gnoshbot/${local.environment}"

  database_url = coalesce(
    try(neon_project.control[0].connection_uri_pooler, ""),
    var.neon_pooled_database_url
  )
  skip_log_hmac_secret = var.skip_log_hmac_secret != "" ? var.skip_log_hmac_secret : random_password.skip_hmac.result
  menu_wrap_key_hex    = var.menu_wrap_key_hex != "" ? var.menu_wrap_key_hex : random_bytes.menu_wrap.hex
}
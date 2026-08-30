# Never inherit the operator default profile (this machine's default is us-east-1).
# Pass AWS_PROFILE=gnoshbot-staging or gnoshbot-prod. GROK.md T01/T04, SCALABILITY.md S1.

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project     = "gnoshbot"
      Environment = local.environment
      ManagedBy   = "terraform"
      RegionPin   = local.region
      Shape       = "cheap"
    }
  }
}

provider "neon" {
  api_key = var.neon_api_key == "" ? "not-used-when-manage_neon-is-false" : var.neon_api_key
}

locals {
  region = "us-west-2"
}

variable "aws_profile" {
  type        = string
  description = "Deploy profile. Region on the profile must already be us-west-2 (N0)."
  default     = "gnoshbot-staging"
}

variable "state_bucket" {
  type        = string
  description = "Globally unique S3 bucket for Terraform state. Must live in us-west-2."
  default     = "gnoshbot-tfstate-us-west-2"
}

variable "lock_table" {
  type        = string
  description = "DynamoDB lock table in us-west-2."
  default     = "gnoshbot-terraform-lock"
}

provider "aws" {
  region  = local.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "gnoshbot"
      ManagedBy = "terraform"
      Purpose   = "terraform-state"
      RegionPin = "us-west-2"
    }
  }
}

check "bootstrap_region" {
  assert {
    condition     = local.region == "us-west-2"
    error_message = "GROK T01/T04: Terraform state backend must be created in us-west-2."
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate_tls_and_region" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "DenyS3ApiOutsideUsWest2"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          StringNotEquals = { "aws:RequestedRegion" = "us-west-2" }
        }
      }
    ]
  })
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_region" {
  value = aws_s3_bucket.tfstate.region
}

output "lock_table" {
  value = aws_dynamodb_table.lock.name
}

output "lock_table_arn" {
  value = aws_dynamodb_table.lock.arn
}

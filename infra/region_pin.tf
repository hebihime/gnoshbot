# Cheap workspace: Neon + two Lambdas + SSM. No RDS, ECR wait is N5; no ALB/NAT/SQS.
# Region pin remains terraform_data.region_pin (N0).

check "compute_in_us_west_2" {
  assert {
    condition     = local.region == "us-west-2"
    error_message = "GROK T01/T04: Gnoshbot AWS must be us-west-2 (Overture catalog overturemaps-us-west-2)."
  }
}

check "overture_bucket_in_region" {
  assert {
    condition     = local.overture_bucket == "overturemaps-us-west-2"
    error_message = "GROK T01: catalog bucket is overturemaps-us-west-2, not the us-east-1 twin."
  }
}

resource "terraform_data" "region_pin" {
  input = {
    region          = local.region
    overture_bucket = local.overture_bucket
    environment     = local.environment
  }

  lifecycle {
    precondition {
      condition     = local.region == "us-west-2"
      error_message = "Refusing to plan outside us-west-2."
    }

    precondition {
      condition     = contains(["staging", "prod", "default"], terraform.workspace)
      error_message = "Workspace must be staging or prod (default is local empty plan only)."
    }
  }
}

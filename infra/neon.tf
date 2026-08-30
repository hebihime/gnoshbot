check "neon_region_is_oregon" {
  assert {
    condition     = local.neon_region == "aws-us-west-2"
    error_message = "Neon must be aws-us-west-2 so PostGIS sits next to Overture ingest."
  }
}

resource "neon_project" "control" {
  count      = var.manage_neon ? 1 : 0
  name       = local.name_prefix
  region_id  = local.neon_region
  pg_version = 16
  org_id     = var.neon_org_id == "" ? null : var.neon_org_id

  # Hobby: short PITR, small CU, suspend when idle. Not Multi-AZ RDS.
  history_retention_seconds = 21600

  default_endpoint_settings {
    autoscaling_limit_min_cu = 0.25
    autoscaling_limit_max_cu = 2
    suspend_timeout_seconds  = 300
  }

  branch {
    database_name = "gnoshbot"
  }

  lifecycle {
    precondition {
      condition     = var.neon_api_key != ""
      error_message = "manage_neon=true requires neon_api_key / NEON_API_KEY."
    }
    precondition {
      condition     = local.neon_region == "aws-us-west-2"
      error_message = "Refusing Neon outside aws-us-west-2."
    }
  }
}

resource "null_resource" "init_sql" {
  count = var.manage_neon ? 1 : 0

  triggers = {
    project_id = neon_project.control[0].id
    schema_sha = filesha256("${path.module}/../database/init.sql")
  }

  provisioner "local-exec" {
    environment = {
      # Direct (non-pooler) URL: CREATE EXTENSION / indexes. App uses the pooled URL.
      DATABASE_URL = neon_project.control[0].connection_uri
    }
    command = "psql \"$DATABASE_URL\" -v ON_ERROR_STOP=1 -f \"${path.module}/../database/init.sql\""
  }
}

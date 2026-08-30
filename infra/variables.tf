variable "manage_neon" {
  type        = bool
  description = "Create a Neon project in aws-us-west-2. Set false for local terraform plan without a Neon API key."
  default     = true
}

variable "neon_api_key" {
  type        = string
  sensitive   = true
  description = "Neon API key (NEON_API_KEY). Required when manage_neon is true."
  default     = ""
}

variable "neon_org_id" {
  type        = string
  description = "Optional Neon org id."
  default     = ""
}

variable "neon_pooled_database_url" {
  type        = string
  sensitive   = true
  description = "Pooled Neon URL when manage_neon is false (sslmode=require). Apply schema with scripts/apply-schema.sh on the direct host."
  default     = ""
}

variable "skip_log_hmac_secret" {
  type        = string
  sensitive   = true
  description = "SKIP_LOG_HMAC_SECRET. Generated if empty."
  default     = ""
}

variable "menu_wrap_key_hex" {
  type        = string
  sensitive   = true
  description = "MENU_WRAP_KEY_HEX (32-byte hex). Generated if empty."
  default     = ""
}

variable "overture_release" {
  type        = string
  description = "Pinned Overture release id (GROK T02)."
  default     = "2026-08-19.0"
}

variable "image_tag" {
  type        = string
  description = "ECR tag for gnoshbot-backend (linux/amd64)."
  default     = "latest"
}

variable "monthly_budget_usd" {
  type        = string
  description = "AWS Budgets alarm for us-west-2. Hobby-scale, not a hard cap."
  default     = "15"
}

variable "notification_email" {
  type        = string
  description = "Budget and ingest-duration alarm email. Empty skips email actions."
  default     = ""
}

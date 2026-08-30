# Region pin for all Gnoshbot AWS. GROK.md T01/T04, SCALABILITY.md S1, ARCHITECTURE.md §10.
# Overture catalog is s3://overturemaps-us-west-2; same-region GET is $0 transfer (GET request charges still apply).

locals {
  region          = "us-west-2"
  overture_bucket = "overturemaps-us-west-2"
  overture_prefix = "release/*"
  environments    = ["gnoshbot-staging", "gnoshbot-prod"]
}

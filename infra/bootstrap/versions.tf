terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state on purpose: this stack creates the remote backend.
  backend "local" {
    path = "terraform.tfstate"
  }
}

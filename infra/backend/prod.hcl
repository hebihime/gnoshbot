bucket         = "gnoshbot-tfstate-us-west-2"
key            = "prod/control-plane.tfstate"
region         = "us-west-2"
dynamodb_table = "gnoshbot-terraform-lock"
encrypt        = true
profile        = "gnoshbot-prod"

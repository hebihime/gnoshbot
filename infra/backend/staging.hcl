bucket         = "gnoshbot-tfstate-us-west-2"
key            = "staging/control-plane.tfstate"
region         = "us-west-2"
dynamodb_table = "gnoshbot-terraform-lock"
encrypt        = true
profile        = "gnoshbot-staging"

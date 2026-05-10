terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "quantlake-admin"

  default_tags {
    tags = {
      Project = "quantlake"
      Env     = "dev"
      Owner   = "dragonslayer"
    }
  }
}
terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.44.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.49.0"
    }
  }

  required_version = "~> 1.2"
}
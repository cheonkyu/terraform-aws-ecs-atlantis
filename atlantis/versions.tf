terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    github = {
      source  = "integrations/github"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }

  backend "s3" {
    region  = "ap-northeast-2"
    bucket  = "cheonkyu-atlantics-tfstate"
    key     = "atlantics/terraform.tfstate"
    profile = "default"
  }
}

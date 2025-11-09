terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

provider "aws" {
  region = var.region
}

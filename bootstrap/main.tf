# The state bucket cannot live in the state it stores, so this tiny config runs
# once with local state to create it. Everything afterwards uses the S3 backend.
#
#   cd bootstrap
#   terraform init
#   terraform apply -var aws_account_id=...

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "aws_profile" {
  type    = string
  default = null
}

variable "aws_account_id" {
  type = string
}

provider "aws" {
  region              = var.aws_region
  profile             = var.aws_profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = "operafy"
      ManagedBy = "terraform"
      Purpose   = "remote-state"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = "operafy-tfstate-${var.aws_account_id}"

  # State is the one thing you cannot rebuild from source.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "Pass this to terraform init -backend-config=\"bucket=...\" in the root module."
}

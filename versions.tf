terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in S3, locked with a native S3 lock file (Terraform 1.10+),
  # so there is no DynamoDB table to pay for or keep in sync.
  # Create the bucket first with the config in ./bootstrap.
  backend "s3" {
    key          = "operafy/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

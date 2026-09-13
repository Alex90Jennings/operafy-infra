locals {
  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Repo      = "Alex90Jennings/operafy-infra"
  }
}

# allowed_account_ids is a guard rail, not decoration. A wrong AWS_PROFILE would
# otherwise apply this plan to whichever account it resolves to. Terraform refuses to run if the account does not match.
provider "aws" {
  region              = var.aws_region
  profile             = var.aws_profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

# CloudFront only reads certificates from us-east-1, whatever region the
# rest of the stack lives in.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  profile             = var.aws_profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

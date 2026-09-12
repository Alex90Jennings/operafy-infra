variable "project" {
  description = "Name prefix for every resource in this stack."
  type        = string
  default     = "operafy"
}

variable "aws_region" {
  description = "Region for the bucket and any regional resources."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "Local AWS profile to authenticate with. Leave null in CI, where OIDC supplies credentials."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "Account this stack is allowed to touch. Terraform aborts against any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12 digit AWS account ID."
  }
}

variable "domain_name" {
  description = "Optional custom domain for the CDN, for example media.example.com. Empty means use the CloudFront domain and skip ACM entirely."
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 is Europe and North America only, and is the cheapest."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "How long superseded object versions are kept before being deleted."
  type        = number
  default     = 30
}

variable "enable_github_oidc" {
  description = "Create the GitHub Actions OIDC provider and deploy role. Needs IAM permissions to apply."
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "owner/repo allowed to assume the deploy role."
  type        = string
  default     = "Alex90Jennings/operafy-infra"
}

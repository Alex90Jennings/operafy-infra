# GitHub Actions authenticates by exchanging a short lived OIDC token for this
# role. No access key is ever stored in the repository. Gated behind a flag
# because creating it needs IAM permissions the deploy user does not have.

# An account can hold only one OIDC provider per URL, and it may already exist
# from earlier work. Set github_oidc_provider_arn to reuse that one; leave it
# empty and this creates it. A data source alone would fail on a fresh account,
# and an unconditional resource would collide on an account that already has it.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc && var.github_oidc_provider_arn == "" ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer verifies this thumbprint for the GitHub provider, but the
  # argument is still required.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  state_bucket_arn = var.state_bucket == "" ? "" : "arn:aws:s3:::${var.state_bucket}"

  github_subject_claim = var.github_subject_claim != "" ? var.github_subject_claim : "repo:${var.github_repository}:*"

  github_oidc_arn = var.enable_github_oidc ? (
    var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
  ) : null
}

data "aws_iam_policy_document" "github_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to one repository. Without this condition any GitHub repository
    # in the world could assume the role.
    #
    # This organisation emits a customised subject claim that embeds the numeric
    # owner and repository IDs, so the documented "repo:owner/name:*" pattern
    # never matches. Pinning the IDs is the stronger form anyway: they are
    # immutable, so renaming the repo or the account cannot hand this role to
    # whoever claims the freed up name.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_subject_claim]
    }
  }
}

resource "aws_iam_role" "deploy" {
  count = var.enable_github_oidc ? 1 : 0

  name               = "${var.project}-github-deploy"
  description        = "Assumed by GitHub Actions to sync media and invalidate the CDN"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json
}

# The CI role does two jobs: it runs Terraform against this stack, and it syncs
# media. Both are scoped to named resources wherever the API supports it.
data "aws_iam_policy_document" "deploy" {
  count = var.enable_github_oidc ? 1 : 0

  # Terraform state, including the lock object it writes beside the state file.
  dynamic "statement" {
    for_each = local.state_bucket_arn == "" ? [] : [1]

    content {
      sid       = "TerraformStateBucket"
      effect    = "Allow"
      actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
      resources = [local.state_bucket_arn]
    }
  }

  dynamic "statement" {
    for_each = local.state_bucket_arn == "" ? [] : [1]

    content {
      sid       = "TerraformStateObjects"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = ["${local.state_bucket_arn}/*"]
    }
  }

  # The media bucket: both managing it and syncing objects into it.
  statement {
    sid       = "ManageTheMediaBucket"
    effect    = "Allow"
    actions   = ["s3:Get*", "s3:List*", "s3:Put*", "s3:Delete*"]
    resources = [aws_s3_bucket.media.arn, "${aws_s3_bucket.media.arn}/*"]
  }

  # CloudFront distribution and OAC management. Create and List calls are
  # account level in the CloudFront API and cannot be scoped to a resource,
  # so they are separated from the calls that can be.
  statement {
    sid    = "CloudFrontResourceScoped"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:CreateInvalidation",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
    ]
    resources = [aws_cloudfront_distribution.media.arn]
  }

  statement {
    sid    = "CloudFrontAccountLevel"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:ListDistributions",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetOriginAccessControlConfig",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:ListOriginAccessControls",
      "cloudfront:ListCachePolicies",
      "cloudfront:ListOriginRequestPolicies",
      "cloudfront:ListResponseHeadersPolicies",
    ]
    resources = ["*"]
  }

  # IAM is scoped to this role and this provider only. Without these ARNs the
  # role could rewrite its own permissions, which is a privilege escalation
  # dressed up as a deploy step.
  statement {
    sid    = "ManageOwnRoleOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [aws_iam_role.deploy[0].arn]
  }

  statement {
    sid       = "ReadTheOIDCProvider"
    effect    = "Allow"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [local.github_oidc_arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  count = var.enable_github_oidc ? 1 : 0

  name   = "${var.project}-media-sync"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy[0].json
}

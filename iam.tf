# GitHub Actions authenticates by exchanging a short lived OIDC token for this
# role. No access key is ever stored in the repository. Gated behind a flag
# because creating it needs IAM permissions the deploy user does not have.

data "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to one repository. Without this condition any GitHub repository
    # in the world could assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  count = var.enable_github_oidc ? 1 : 0

  name               = "${var.project}-github-deploy"
  description        = "Assumed by GitHub Actions to sync media and invalidate the CDN"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json
}

# Exactly the actions a media sync needs, on exactly this bucket and this
# distribution. No wildcards on resources.
data "aws_iam_policy_document" "deploy" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid       = "ListTheMediaBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.media.arn]
  }

  statement {
    sid    = "ReadWriteMediaObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.media.arn}/*"]
  }

  statement {
    sid       = "InvalidateTheDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.media.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  count = var.enable_github_oidc ? 1 : 0

  name   = "${var.project}-media-sync"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy[0].json
}

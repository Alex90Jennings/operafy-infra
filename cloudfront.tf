# Origin Access Control is how a private bucket is read by CloudFront and
# nothing else. It replaces the older Origin Access Identity, and it signs
# requests with SigV4 rather than relying on a shared identity.
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.project}-media"
  description                       = "Signed access from CloudFront to the ${var.project} media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Managed policies rather than hand rolled ones: AWS keeps them current, and
# CachingOptimized already does the right thing for immutable media.
data "aws_cloudfront_cache_policy" "optimised" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "cors_s3" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "media" {
  enabled         = true
  comment         = "${var.project} media CDN"
  price_class     = var.price_class
  http_version    = "http2and3"
  is_ipv6_enabled = true

  aliases = var.domain_name == "" ? [] : [var.domain_name]

  origin {
    origin_id                = "s3-${aws_s3_bucket.media.id}"
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.media.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Audio and images are read only. Anything else is a bug, not a feature.
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = data.aws_cloudfront_cache_policy.optimised.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.cors_s3.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # With no custom domain, the default *.cloudfront.net certificate is used
    # and there is no ACM certificate to issue, validate or pay attention to.
    cloudfront_default_certificate = var.domain_name == ""
    acm_certificate_arn            = var.domain_name == "" ? null : aws_acm_certificate_validation.media[0].certificate_arn
    ssl_support_method             = var.domain_name == "" ? null : "sni-only"
    minimum_protocol_version       = var.domain_name == "" ? "TLSv1" : "TLSv1.2_2021"
  }
}

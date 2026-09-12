output "bucket_name" {
  description = "Media bucket. Private: reachable only through CloudFront."
  value       = aws_s3_bucket.media.id
}

output "cdn_domain" {
  description = "Hostname to serve media from."
  value       = var.domain_name == "" ? aws_cloudfront_distribution.media.domain_name : var.domain_name
}

output "cdn_url" {
  description = "Base URL for media objects."
  value       = "https://${var.domain_name == "" ? aws_cloudfront_distribution.media.domain_name : var.domain_name}"
}

output "distribution_id" {
  description = "Needed to create cache invalidations."
  value       = aws_cloudfront_distribution.media.id
}

output "deploy_role_arn" {
  description = "Role for GitHub Actions to assume. Null unless enable_github_oidc is set."
  value       = var.enable_github_oidc ? aws_iam_role.deploy[0].arn : null
}

output "certificate_validation_records" {
  description = "DNS records to create at the domain's DNS provider so ACM can issue the certificate."
  value = var.domain_name == "" ? [] : [
    for o in aws_acm_certificate.media[0].domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

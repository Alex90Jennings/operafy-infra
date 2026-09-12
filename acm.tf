# Everything here is skipped entirely when domain_name is empty, which keeps
# the default stack free of DNS validation steps that would otherwise block
# the first apply.

resource "aws_acm_certificate" "media" {
  count = var.domain_name == "" ? 0 : 1

  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS for this domain is not hosted in this account, so the validation record
# is emitted as an output and added at the DNS provider by hand. Terraform then
# waits for the certificate to be issued.
resource "aws_acm_certificate_validation" "media" {
  count = var.domain_name == "" ? 0 : 1

  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.media[0].arn

  timeouts {
    create = "30m"
  }
}

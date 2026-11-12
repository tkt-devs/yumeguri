output "certificate_arn" {
  description = "検証が終わった証明書の ARN（これを使えば、検証の前に ALB・CloudFront に付けようとして失敗することがない）"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

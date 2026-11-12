output "distribution_arn" {
  description = "バケットポリシーで「このディストリビューションだけ読める」とするのに使う"
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

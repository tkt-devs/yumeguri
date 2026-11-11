output "bucket_names" {
  description = "バケットの名前（private・public・logs）"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "バケットの ARN（IAM のロールで許可するときに使う。S1-15）"
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "bucket_regional_domain_names" {
  description = "バケットのドメイン名（リージョンつき。CloudFront のオリジンに使う）"
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket_regional_domain_name }
}

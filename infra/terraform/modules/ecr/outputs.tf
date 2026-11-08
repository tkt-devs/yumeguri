output "repository_urls" {
  description = "イメージの名前の前半（<アカウント>.dkr.ecr.<リージョン>.amazonaws.com/<名前>）"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "IAM のロールで、イメージの取得を許可するときに使う"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

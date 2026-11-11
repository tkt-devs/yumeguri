output "origin_header_name" {
  value = var.header_name
}

output "origin_header_secret_arn" {
  description = "秘密のヘッダーの値が入った Secrets Manager の ARN（ALB のルールが読む）"
  # 版（値）の ARN を通すので、値を入れ終わってから渡る（入れる前に読むと失敗する）
  value = aws_secretsmanager_secret_version.origin_header.secret_arn
}

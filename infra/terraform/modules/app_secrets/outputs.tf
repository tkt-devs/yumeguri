output "secret_arns" {
  description = "シークレットの ARN（ECS のタスク定義の secrets と、IAM のロールで使う。S1-15）"
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

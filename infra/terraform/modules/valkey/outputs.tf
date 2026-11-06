output "primary_endpoint" {
  description = "Valkey の接続先のホスト名（TLS なので rediss:// でつなぐ）"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "auth_secret_arn" {
  description = "AUTH トークンのシークレット（S1-15 のタスク定義で使う）"
  value       = aws_secretsmanager_secret.auth.arn
}

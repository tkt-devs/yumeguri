output "endpoint" {
  description = "RDS の接続先（ホスト名:ポート）"
  value       = aws_db_instance.this.endpoint
}

output "master_user_secret_arn" {
  description = "管理者のパスワードのシークレット（RDS が作ったもの）。DB のユーザーを作る単発のタスクだけが読む"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "db_user_secret_arns" {
  description = "アプリ用の DB のユーザーのパスワードのシークレット（S1-15 のタスク定義で使う）"
  value       = { for k, s in aws_secretsmanager_secret.db_user : k => s.arn }
}

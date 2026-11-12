output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

# API・ワーカーのタスク実行ロールが書いてよいロググループ（DB の準備用は、別のロールが書く）
output "log_group_arns" {
  value = [for k in ["api", "worker"] : aws_cloudwatch_log_group.this[k].arn]
}

output "db_tasks_log_group_arn" {
  value = aws_cloudwatch_log_group.this["db-tasks"].arn
}

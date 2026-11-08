output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "log_group_arns" {
  value = [for g in aws_cloudwatch_log_group.this : g.arn]
}

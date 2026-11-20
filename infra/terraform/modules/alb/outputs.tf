output "dns_name" {
  description = "ALB の DNS 名（Cloudflare の api. をここに向ける）"
  value       = aws_lb.this.dns_name
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
  # ECS のサービスは、ALB のリスナーにつながったターゲットグループでないと作れない
  # （先にサービスを作ろうとすると "does not have an associated load balancer" で止まる）
  depends_on = [aws_lb_listener_rule.api]
}

# CloudWatch のメトリクスで使う名前（app/<名前>/<ID>・targetgroup/<名前>/<ID>。S1-20 のアラーム）
output "arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "api_target_group_arn_suffix" {
  value = aws_lb_target_group.api.arn_suffix
}

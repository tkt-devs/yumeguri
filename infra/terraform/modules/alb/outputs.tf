output "dns_name" {
  description = "ALB の DNS 名（S1-16 で、Cloudflare の api. をここに向ける）"
  value       = aws_lb.this.dns_name
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
  # ECS のサービスは、ALB のリスナーにつながったターゲットグループでないと作れない
  # （先にサービスを作ろうとすると "does not have an associated load balancer" で止まる）
  depends_on = [aws_lb_listener.http]
}

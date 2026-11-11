# S1-15（ECS のタスクのロール・タスク定義）で使う
output "bucket_names" {
  value = module.buckets.bucket_names
}

output "bucket_arns" {
  value = module.buckets.bucket_arns
}

output "queue_urls" {
  value = module.queues.queue_urls
}

output "queue_arns" {
  value = module.queues.queue_arns
}

output "app_secret_arns" {
  value = module.app_secrets.secret_arns
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  value = module.ecr.repository_arns
}

# S1-16（envs/staging の ALB・api. の DNS）で使う
output "cloudflare_zone_id" {
  value = data.cloudflare_zone.this.id
}

output "hosts" {
  description = "ホスト名（api.・app.・img.）。証明書・Cloudflare のルールと同じ値を、envs/staging でも使う"
  value       = local.hosts
}

output "alb_log_prefix" {
  value = local.alb_log_prefix
}

output "api_certificate_arn" {
  value = module.api_cert.certificate_arn
}

output "origin_header_name" {
  value = module.edge.origin_header_name
}

output "origin_header_secret_arn" {
  value = module.edge.origin_header_secret_arn
}

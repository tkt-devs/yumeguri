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

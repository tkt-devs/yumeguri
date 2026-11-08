output "vpc_id" {
  value = module.network.vpc_id
}

output "nat_instance_id" {
  value = module.network.nat_instance_id
}

output "security_group_ids" {
  value = module.network.security_group_ids
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "valkey_endpoint" {
  value = module.valkey.primary_endpoint
}

output "rds_master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "db_user_secret_arns" {
  value = module.rds.db_user_secret_arns
}

output "valkey_auth_secret_arn" {
  value = module.valkey.auth_secret_arn
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

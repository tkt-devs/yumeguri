output "vpc_id" {
  value = module.network.vpc_id
}

output "nat_instance_id" {
  value = module.network.nat_instance_id
}

output "security_group_ids" {
  value = module.network.security_group_ids
}

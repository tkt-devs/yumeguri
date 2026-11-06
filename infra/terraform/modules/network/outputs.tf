output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "公開のサブネット（ALB を置く。azs と同じ順番）"
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "非公開のサブネット（ECS・RDS・ElastiCache を置く。azs と同じ順番）"
  value       = [for az in var.azs : aws_subnet.private[az].id]
}

output "security_group_ids" {
  description = "S1-14（RDS・ElastiCache）、S1-15（ECS）、S1-16（ALB）で使う"
  value = {
    alb    = aws_security_group.alb.id
    api    = aws_security_group.api.id
    worker = aws_security_group.worker.id
    rds    = aws_security_group.rds.id
    valkey = aws_security_group.valkey.id
  }
}

output "nat_instance_id" {
  description = "NAT の EC2（Session Manager で入るときに使う）"
  value       = aws_instance.nat.id
}

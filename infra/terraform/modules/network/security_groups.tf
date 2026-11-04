# セキュリティグループ（AWS 構成図 v0.1 の表のとおり）
# 送り元・送り先は、IP アドレスではなく、別のセキュリティグループで指定する（Cloudflare と外への 443 だけは例外）
# Terraform は、セキュリティグループを作るとき、AWS が自動で付ける「外へは全部許す」ルールを消す。
# なので、ここに書いたルールだけが通る
# description（説明）は、AWS の決まりで英数字と一部の記号しか使えない（日本語は不可）

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB: HTTPS from Cloudflare only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "api" {
  name        = "${var.name}-api"
  description = "API tasks: from ALB only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-api" }
}

resource "aws_security_group" "worker" {
  name        = "${var.name}-worker"
  description = "Worker tasks: no inbound"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-worker" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS: 5432 from API and worker tasks"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-rds" }
}

resource "aws_security_group" "valkey" {
  name        = "${var.name}-valkey"
  description = "ElastiCache: 6379 from API tasks"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-valkey" }
}

resource "aws_security_group" "nat" {
  name        = "${var.name}-nat"
  description = "NAT instance: relays HTTPS from tasks"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-nat" }
}

locals {
  # ECS のタスク（API・ワーカー）。DB に入る・外へ出る（NAT の EC2 を通る）ところが同じ
  task_sgs = {
    api    = aws_security_group.api.id
    worker = aws_security_group.worker.id
  }
}

# ---- ALB ----

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudflare" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from Cloudflare"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To API tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.api.id
}

# ---- API ----

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.api.id
  description                  = "From ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "api_to_valkey" {
  security_group_id            = aws_security_group.api.id
  description                  = "To ElastiCache"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.valkey.id
}

# ---- API・ワーカーの共通（DB と、外への 443） ----

resource "aws_vpc_security_group_egress_rule" "task_to_rds" {
  for_each = local.task_sgs

  security_group_id            = each.value
  description                  = "To RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

# 外（NAT の EC2 を通る）と、S3（ゲートウェイエンドポイントを通る）への 443
resource "aws_vpc_security_group_egress_rule" "task_to_internet" {
  for_each = local.task_sgs

  security_group_id = each.value
  description       = "HTTPS to the internet and S3"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---- RDS・ElastiCache（受けるだけ。外へ出るルールはない） ----

resource "aws_vpc_security_group_ingress_rule" "rds_from_task" {
  for_each = local.task_sgs

  security_group_id            = aws_security_group.rds.id
  description                  = "From ${each.key} tasks"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "valkey_from_api" {
  security_group_id            = aws_security_group.valkey.id
  description                  = "From API tasks"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.api.id
}

# ---- NAT の EC2 ----

resource "aws_vpc_security_group_ingress_rule" "nat_from_task" {
  for_each = local.task_sgs

  security_group_id            = aws_security_group.nat.id
  description                  = "HTTPS from ${each.key} tasks"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = each.value
}

# 中継した通信と、NAT の EC2 自身の通信（OS の更新・Session Manager）を外へ出す
resource "aws_vpc_security_group_egress_rule" "nat_to_internet" {
  security_group_id = aws_security_group.nat.id
  description       = "HTTPS to the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

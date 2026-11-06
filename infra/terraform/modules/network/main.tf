# VPC・サブネット・インターネットゲートウェイ・ルートテーブル・S3 のゲートウェイエンドポイント
# 形は「AWS 構成図 v0.1」のとおり：2つの AZ × 公開・非公開のサブネット

locals {
  # AZ の名前 → IP アドレスの範囲（for_each で、AZ ごとに1つずつ作るため）
  public_subnets  = zipmap(var.azs, var.public_subnet_cidrs)
  private_subnets = zipmap(var.azs, var.private_subnet_cidrs)
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # VPC の中で名前解決を使う（ECS・RDS・VPC エンドポイントが、DNS 名で相手を探すため）
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

# VPC を作ると自動でできる「既定のセキュリティグループ」の許可を、全部外す
# （うっかり既定のものを付けたとき、通信が通ってしまわないように）
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

# ---- 公開のサブネット（ALB・NAT の EC2） ----

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  # ここに置いたものに、自動で公開の IP を付けない（付けるものは、個別に付ける）
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public" }
}

# 公開のサブネットから外（0.0.0.0/0）へは、インターネットゲートウェイを通る
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---- 非公開のサブネット（ECS のタスク・RDS・ElastiCache） ----

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name}-private-${each.key}" }
}

# NAT の EC2 が1台なので、非公開のサブネットのルートテーブルも1つにして、2つの AZ で共有する
# 外（0.0.0.0/0）への道は nat.tf に書く
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ---- S3 のゲートウェイ型の VPC エンドポイント（無料） ----
# 非公開のルートテーブルに「S3 への道」が足される。S3 への通信が NAT の EC2 を通らなくなる
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name}-s3" }
}

data "aws_region" "current" {}

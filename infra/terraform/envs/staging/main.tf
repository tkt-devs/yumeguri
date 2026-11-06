# staging の「使うときだけの層」（ADR-022）：VPC・NAT・RDS・ElastiCache。modules/ の部品を、ここで組み合わせる

# Cloudflare の IP アドレスの範囲（公開の情報なので、API のトークンは要らない）
# apply のたびに最新を取り直す（ADR-013：一覧は変わることがある）
data "cloudflare_ip_ranges" "this" {}

# ネットワーク（S1-13）。IP アドレスの範囲は「AWS 構成図 v0.1」のとおり
module "network" {
  source = "../../modules/network"

  name                 = "yumeguri-staging"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  # ALB は IPv4 だけで受けるので、IPv4 の範囲だけを渡す
  alb_ingress_cidrs = data.cloudflare_ip_ranges.this.ipv4_cidrs
}

# DB（S1-14）。非公開のサブネットに置き、門番 rds を付ける
module "rds" {
  source = "../../modules/rds"

  name              = "yumeguri-staging"
  secret_prefix     = "yumeguri/staging"
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.security_group_ids["rds"]
}

# 短い値の置き場所（S1-14）。非公開のサブネットに置き、門番 valkey を付ける
module "valkey" {
  source = "../../modules/valkey"

  name              = "yumeguri-staging"
  secret_prefix     = "yumeguri/staging"
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.security_group_ids["valkey"]
}

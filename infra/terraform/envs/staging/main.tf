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

# ---- コンピュート（S1-15） ----

# ずっと残す層（envs/staging-persistent）の出力を読む：バケット・キュー・シークレット・ECR
data "terraform_remote_state" "persistent" {
  backend = "s3"
  config = {
    bucket = "yumeguri-tfstate-staging"
    key    = "envs/staging-persistent/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

locals {
  persistent = data.terraform_remote_state.persistent.outputs
  api_port   = 3001

  # API・ワーカーに共通で渡す、見られても困らない環境変数
  shared_environment = {
    LOG_LEVEL             = "info"
    AWS_REGION            = "ap-northeast-1"
    SQS_QUEUE_URL_DEFAULT = local.persistent.queue_urls["jobs-default"]
    SQS_QUEUE_URL_HEAVY   = local.persistent.queue_urls["jobs-heavy"]
  }
}

# 試しの間だけ：自分の IP から ALB の 80（HTTP）を受ける（S1-15）
# S1-16 で HTTPS と Cloudflare に切り替えたら、このブロックと var.alb_test_ingress_cidrs を消す
resource "aws_vpc_security_group_ingress_rule" "alb_test_http" {
  for_each = toset(var.alb_test_ingress_cidrs)

  security_group_id = module.network.security_group_ids["alb"]
  description       = "Temporary HTTP for testing"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

module "iam_ecs" {
  source = "../../modules/iam_ecs"

  name                = "yumeguri-staging"
  ecr_repository_arns = values(local.persistent.ecr_repository_arns)
  log_group_arns      = module.ecs.log_group_arns
  # 起動のときに読むのは、API の DB のパスワードだけ（ワーカーは、まだ DB を使わない）
  startup_secret_arns     = [module.rds.db_user_secret_arns["yumeguri_app"]]
  private_bucket_arn      = local.persistent.bucket_arns["private"]
  public_bucket_arn       = local.persistent.bucket_arns["public"]
  queue_arns              = values(local.persistent.queue_arns)
  api_runtime_secret_arns = [local.persistent.app_secret_arns["qr-signing-key"]]
}

module "alb" {
  source = "../../modules/alb"

  name              = "yumeguri-staging"
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  security_group_id = module.network.security_group_ids["alb"]
  target_port       = local.api_port
}

module "ecs" {
  source = "../../modules/ecs"

  name                     = "yumeguri-staging"
  private_subnet_ids       = module.network.private_subnet_ids
  api_security_group_id    = module.network.security_group_ids["api"]
  worker_security_group_id = module.network.security_group_ids["worker"]
  execution_role_arn       = module.iam_ecs.execution_role_arn
  api_task_role_arn        = module.iam_ecs.api_task_role_arn
  worker_task_role_arn     = module.iam_ecs.worker_task_role_arn
  api_image                = "${local.persistent.ecr_repository_urls["yumeguri-api"]}:${var.image_tag}"
  worker_image             = "${local.persistent.ecr_repository_urls["yumeguri-worker"]}:${var.image_tag}"
  api_target_group_arn     = module.alb.api_target_group_arn
  api_port                 = local.api_port

  api_environment = merge(local.shared_environment, {
    NODE_ENV   = "staging"
    PORT       = tostring(local.api_port)
    WEB_ORIGIN = "https://app.stg.sento-stamprally.com"
  })
  # シークレットの JSON の url のキーを、DATABASE_URL として渡す
  api_secrets = {
    DATABASE_URL = "${module.rds.db_user_secret_arns["yumeguri_app"]}:url::"
  }

  worker_environment = local.shared_environment
}

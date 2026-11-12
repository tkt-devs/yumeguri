# staging の「使うときだけの層」（ADR-022）：VPC・NAT・RDS・ElastiCache・ECS・ALB・api. の DNS。modules/ の部品を、ここで組み合わせる

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

# 動かすイメージのタグ（Git のコミット ID）。CD（.github/workflows/cd.yml）が、ずっと残す層の SSM のパラメータに書く
# up のたびに、いちばん新しくデプロイしたイメージで作り直される
data "aws_ssm_parameter" "image_tag" {
  name = data.terraform_remote_state.persistent.outputs.image_tag_parameter_name
}

locals {
  persistent = data.terraform_remote_state.persistent.outputs
  api_port   = 3001
  image_tag  = data.aws_ssm_parameter.image_tag.insecure_value
  db_users   = module.rds.db_user_secret_arns

  # API・ワーカーに共通で渡す、見られても困らない環境変数
  shared_environment = {
    LOG_LEVEL             = "info"
    AWS_REGION            = "ap-northeast-1"
    SQS_QUEUE_URL_DEFAULT = local.persistent.queue_urls["jobs-default"]
    SQS_QUEUE_URL_HEAVY   = local.persistent.queue_urls["jobs-heavy"]
  }
}

module "iam_ecs" {
  source = "../../modules/iam_ecs"

  name                = "yumeguri-staging"
  ecr_repository_arns = values(local.persistent.ecr_repository_arns)
  log_group_arns      = module.ecs.log_group_arns
  # DB の準備用の単発のタスク（S1-17）
  db_tasks_ecr_repository_arn = local.persistent.ecr_repository_arns["yumeguri-db-tasks"]
  db_tasks_log_group_arn      = module.ecs.db_tasks_log_group_arn
  db_tasks_secret_arns        = concat([module.rds.master_user_secret_arn], values(local.db_users))
  # 起動のときに読むのは、API の DB のパスワードだけ（ワーカーは、まだ DB を使わない）
  startup_secret_arns     = [local.db_users["yumeguri_app"]]
  private_bucket_arn      = local.persistent.bucket_arns["private"]
  public_bucket_arn       = local.persistent.bucket_arns["public"]
  queue_arns              = values(local.persistent.queue_arns)
  api_runtime_secret_arns = [local.persistent.app_secret_arns["qr-signing-key"]]
}

# ---- 入口（S1-16） ----

# Cloudflare が付ける秘密のヘッダーの値（ずっと残す層が作り、Secrets Manager に置いたもの）
data "aws_secretsmanager_secret_version" "origin_header" {
  secret_id = local.persistent.origin_header_secret_arn
}

module "alb" {
  source = "../../modules/alb"

  name                = "yumeguri-staging"
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  security_group_id   = module.network.security_group_ids["alb"]
  target_port         = local.api_port
  certificate_arn     = local.persistent.api_certificate_arn
  origin_header_name  = local.persistent.origin_header_name
  origin_header_value = data.aws_secretsmanager_secret_version.origin_header.secret_string
  access_log_bucket   = local.persistent.bucket_names["logs"]
  access_log_prefix   = local.persistent.alb_log_prefix
}

# api. を ALB に向ける。Cloudflare のプロキシを有効にする（オレンジの雲）
# ALB の DNS 名は作り直すたびに変わるので、ALB と同じ「使うときだけの層」に置く
resource "cloudflare_dns_record" "api" {
  zone_id = local.persistent.cloudflare_zone_id
  name    = local.persistent.hosts.api
  type    = "CNAME"
  content = module.alb.dns_name
  ttl     = 1 # プロキシを有効にしたレコードは「自動」（1）にする
  proxied = true
  comment = "ALB (Terraform)"
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
  api_image                = "${local.persistent.ecr_repository_urls["yumeguri-api"]}:${local.image_tag}"
  worker_image             = "${local.persistent.ecr_repository_urls["yumeguri-worker"]}:${local.image_tag}"
  api_target_group_arn     = module.alb.api_target_group_arn
  api_port                 = local.api_port

  api_environment = merge(local.shared_environment, {
    NODE_ENV   = "staging"
    PORT       = tostring(local.api_port)
    WEB_ORIGIN = "https://${local.persistent.hosts.app}"
  })
  # シークレットの JSON の url のキーを、DATABASE_URL として渡す
  api_secrets = {
    DATABASE_URL = "${local.db_users["yumeguri_app"]}:url::"
  }

  worker_environment = local.shared_environment

  # DB の準備用の単発のタスク（S1-17）
  db_tasks_image              = "${local.persistent.ecr_repository_urls["yumeguri-db-tasks"]}:${local.image_tag}"
  db_tasks_execution_role_arn = module.iam_ecs.db_tasks_execution_role_arn
  db_tasks = {
    # DB のユーザーを作る（apps/api/scripts/db-bootstrap.ts）。何回動かしても同じ結果になる
    db-bootstrap = {
      command     = ["node_modules/.bin/tsx", "apps/api/scripts/db-bootstrap.ts"]
      memory      = 512
      environment = { DB_HOST = module.rds.address }
      secrets = {
        DB_ADMIN_USERNAME = "${module.rds.master_user_secret_arn}:username::"
        DB_ADMIN_PASSWORD = "${module.rds.master_user_secret_arn}:password::"
        MIGRATOR_PASSWORD = "${local.db_users["yumeguri_migrator"]}:password::"
        APP_PASSWORD      = "${local.db_users["yumeguri_app"]}:password::"
        WORKER_PASSWORD   = "${local.db_users["yumeguri_worker"]}:password::"
      }
    }
    # マイグレーション。流すものがなければ、何もしないで終わる
    # Prisma の CLI は Node.js と schema engine の2つを動かすので、メモリを少し多めにする
    db-migrate = {
      command     = ["node_modules/.bin/prisma", "migrate", "deploy"]
      memory      = 1024
      environment = {}
      # Prisma の書き方の URL（modules/rds の prisma_url）
      secrets = { MIGRATE_DATABASE_URL = "${local.db_users["yumeguri_migrator"]}:prisma_url::" }
    }
  }
}

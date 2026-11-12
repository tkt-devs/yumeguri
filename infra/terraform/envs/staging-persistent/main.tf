# staging の「ずっと残す層」（ADR-022）
# ここにあるものは、down（使うときだけの層を消す）でも消さない：
# - S3：アップロードされたファイル・ログ
# - SQS：キューの URL を変えないため（使っていない間は費用がかからない）
# - シークレットの入れ物：手で入れた値（Google・Sentry など）を、毎回入れ直さないため
# - 入口（S1-16）：証明書・CloudFront・Cloudflare の設定。どれも時間では費用がかからない

locals {
  domain = "sento-stamprally.com"
  # ホスト名は1段（api-stg.…）にする。api.stg.… のような2段のサブドメインは、
  # Cloudflare の無料の証明書（Universal SSL）の対象外で、プロキシすると TLS の接続に失敗する
  hosts = {
    api = "api-stg.${local.domain}"
    app = "app-stg.${local.domain}"
    img = "img-stg.${local.domain}"
  }
  # ALB のアクセスログの置き場所。バケットポリシーの許可と、ALB の設定（envs/staging）で同じ値を使う
  alb_log_prefix = "alb"
}

module "buckets" {
  source = "../../modules/buckets"

  name           = "yumeguri-staging"
  upload_origins = ["https://${local.hosts.app}"]

  # 公開用サムネイルは CloudFront からだけ読める。ログ用には ALB のアクセスログを書ける（S1-16）
  cloudfront_distribution_arns = [module.cdn.distribution_arn]
  alb_log_prefix               = local.alb_log_prefix
}

module "queues" {
  source = "../../modules/queues"
}

module "app_secrets" {
  source = "../../modules/app_secrets"

  prefix = "yumeguri/staging"
  secrets = {
    "google-oauth"   = "Google のログイン（OIDC）のクライアント ID とシークレット（ADR-018）"
    "sentry-dsn"     = "Sentry の DSN（ADR-017）"
    "qr-signing-key" = "QR のトークンに署名する鍵（HMAC-SHA256・kid つき。ADR-015）"
    "session-secret" = "セッションの Cookie に使う鍵（ADR-004）"
  }
}

# コンテナのイメージの置き場所（S1-15）。消すとイメージを押し上げ直すことになるので、ずっと残す層に置く
module "ecr" {
  source = "../../modules/ecr"

  # yumeguri-db-tasks：DB のユーザーの作成・マイグレーションの単発のタスク用（S1-17）
  repositories = ["yumeguri-api", "yumeguri-worker", "yumeguri-db-tasks"]
}

# ---- 自動デプロイ（S1-17・ADR-026） ----

locals {
  # GitHub の身分証の sub。このリポジトリは「変わらない形」（owner と repo の ID 入り）を使う
  # （gh api repos/tkt-devs/yumeguri/actions/oidc/customization/sub の sub_claim_prefix）
  github_main_subject = "repo:tkt-devs@349786052/yumeguri@1439185466:ref:refs/heads/main"
}

# いま staging に出すイメージのタグ（Git のコミット ID）。CD が書き、envs/staging が読む
# 初めの値だけを Terraform で入れる。そのあとは CD が書き換えるので、Terraform は値の違いを無視する
resource "aws_ssm_parameter" "image_tag" {
  name        = "/yumeguri/staging/image-tag"
  description = "staging で動かすイメージのタグ（CD が書き換える）"
  type        = "String"
  value       = "ea2e973558e4"

  lifecycle {
    ignore_changes = [value]
  }
}

module "github_deploy" {
  source = "../../modules/github_deploy"

  # 使うときだけの層（envs/staging）の名前。そこが作るクラスター・ロールなどは、すべてこの名前で始まる
  name                    = "yumeguri-staging"
  allowed_subjects        = [local.github_main_subject]
  ecr_repository_arns     = values(module.ecr.repository_arns)
  image_tag_parameter_arn = aws_ssm_parameter.image_tag.arn
}

# ---- 入口（S1-16・ADR-024） ----

data "cloudflare_zone" "this" {
  filter = {
    name = local.domain
  }
}

# ALB 用の証明書（東京）
module "api_cert" {
  source = "../../modules/acm_cert"

  domain_name = local.hosts.api
  zone_id     = data.cloudflare_zone.this.id
}

# CloudFront 用の証明書（us-east-1 でないと使えない）
module "img_cert" {
  source = "../../modules/acm_cert"
  # providers を書くと、書いたものだけが渡る。Cloudflare も明示して渡す
  providers = {
    aws        = aws.us_east_1
    cloudflare = cloudflare
  }

  domain_name = local.hosts.img
  zone_id     = data.cloudflare_zone.this.id
}

# Cloudflare のゾーンの設定・ルール・秘密のヘッダー
module "edge" {
  source = "../../modules/edge"

  zone_id       = data.cloudflare_zone.this.id
  api_hostname  = local.hosts.api
  secret_prefix = "yumeguri/staging"
}

# 画像の配信（img.）
module "cdn" {
  source = "../../modules/cdn"

  name                        = "yumeguri-staging-img"
  hostname                    = local.hosts.img
  bucket_regional_domain_name = module.buckets.bucket_regional_domain_names["public"]
  certificate_arn             = module.img_cert.certificate_arn
  zone_id                     = data.cloudflare_zone.this.id
}

# Web（app.）は Vercel。値は Vercel のドメインの設定に出るものを、terraform.tfvars に書く
# Cloudflare のプロキシは使わない（Vercel の推奨。ADR-001）
resource "cloudflare_dns_record" "app" {
  count = var.vercel_cname_target == "" ? 0 : 1

  zone_id = data.cloudflare_zone.this.id
  name    = local.hosts.app
  type    = "CNAME"
  content = var.vercel_cname_target
  ttl     = 300
  proxied = false
  comment = "Vercel (Terraform)"
}

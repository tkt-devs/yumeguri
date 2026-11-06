# staging の「ずっと残す層」（ADR-022）
# ここにあるものは、down（使うときだけの層を消す）でも消さない：
# - S3：アップロードされたファイル・ログ
# - SQS：キューの URL を変えないため（使っていない間は費用がかからない）
# - シークレットの入れ物：手で入れた値（Google・Sentry など）を、毎回入れ直さないため

module "buckets" {
  source = "../../modules/buckets"

  name           = "yumeguri-staging"
  upload_origins = ["https://app.stg.sento-stamprally.com"]
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

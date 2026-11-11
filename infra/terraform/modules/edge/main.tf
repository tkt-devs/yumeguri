# Cloudflare の入口の設定（S1-16・ADR-013・ADR-024）
# - ゾーンの設定：Cloudflare から ALB までも HTTPS で、証明書も検証する（Full (strict)）
# - api. へのリクエストに、秘密のヘッダーを付ける（ALB は、これがないリクエストを 403 にする）
# - api. はキャッシュしない
# - Webhook のパスは、WAF のマネージドルールから外す（署名の検証はアプリで行う）
#
# ゾーンの設定とルールは、ゾーン全体に1つずつしか持てない（フェーズごとに1つ）。production（S4-01）で同じゾーンを使うときは、
# この部品を環境ごとに呼ぶと、お互いのルールを上書きしてしまう。そのときは、ゾーン用の root を1つ作り、そこへ移す

# ---- ゾーンの設定 ----

# Full (strict)：Cloudflare → ALB も暗号化し、ALB の証明書が正しいかも確かめる
# （Flexible だと、Cloudflare → ALB が HTTP になり、リダイレクトが無限に続くことがある）
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = "strict"
}

# 古い TLS（1.0・1.1）を断る
resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

# http:// で来たら https:// へ転送する（オレンジの雲のホストだけに効く）
resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# ---- 秘密のヘッダー（ADR-013） ----

# 値は Cloudflare のルールにそのまま書くので、state に残る（Cloudflare 側に「書くだけの引数」がないため）
# state のバケットは非公開・暗号化なので、ここは受け入れる。Secrets Manager にも置き、ALB はそこから読む
resource "random_password" "origin_header" {
  length  = 48
  special = false # ヘッダーの値に使えない記号を避ける
}

resource "aws_secretsmanager_secret" "origin_header" {
  name                    = "${var.secret_prefix}/origin-header"
  description             = "Cloudflare が api. へのリクエストに付ける秘密のヘッダーの値（ADR-013）"
  recovery_window_in_days = 0 # Terraform が作る値なので、消したらすぐ作り直せる
}

resource "aws_secretsmanager_secret_version" "origin_header" {
  secret_id     = aws_secretsmanager_secret.origin_header.id
  secret_string = random_password.origin_header.result
}

# ---- ルール（1つのゾーンに、フェーズごとに1つ） ----

locals {
  api_host_expression = "(http.host eq \"${var.api_hostname}\")"
}

# リクエストのヘッダーを書き換える：api. へのリクエストに秘密のヘッダーを付ける
# operation = "set" なので、利用者が同じ名前のヘッダーを送ってきても、上書きされる
resource "cloudflare_ruleset" "request_headers" {
  zone_id = var.zone_id
  name    = "Origin verification header"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [
    {
      description = "Add the secret header for the ALB"
      expression  = local.api_host_expression
      action      = "rewrite"
      action_parameters = {
        headers = {
          (var.header_name) = {
            operation = "set"
            value     = random_password.origin_header.result
          }
        }
      }
    }
  ]
}

# キャッシュのルール：api. はキャッシュしない（ログインの状態やユーザーごとの応答を、ほかの人に返さないため）
resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "Cache settings"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      description = "Never cache the API"
      expression  = local.api_host_expression
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
    }
  ]
}

# WAF のカスタムルール：Webhook は、外のサービスが機械的に送ってくるので、WAF のマネージドルールで止めない
# （Bot Fight Mode はこの方法では外せないので、有効にしない。公式ドキュメントのとおり）
resource "cloudflare_ruleset" "waf_custom" {
  zone_id = var.zone_id
  name    = "Custom WAF rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      description = "Skip managed rules for webhooks (signatures are verified in the app)"
      expression  = "${local.api_host_expression} and starts_with(http.request.uri.path, \"${var.webhook_path_prefix}\")"
      action      = "skip"
      action_parameters = {
        phases = ["http_request_firewall_managed"]
      }
      logging = {
        enabled = true
      }
    }
  ]
}

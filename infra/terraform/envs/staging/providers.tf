provider "aws" {
  region = "ap-northeast-1"

  # staging のアカウント以外では、plan・apply が止まる
  allowed_account_ids = [var.account_id]

  # このプロバイダーで作るものに、全部自動でタグを付ける
  default_tags {
    tags = {
      project      = "yumeguri"
      env          = "staging"
      "managed-by" = "terraform"
    }
  }
}

# API のトークンは、環境変数 CLOUDFLARE_API_TOKEN から読む（ファイルに書かない。infra/terraform/README.md）
provider "cloudflare" {}

# staging の「ずっと残す層」のプロバイダー（envs/staging と同じ設定）

# このプロバイダーで作るものに、全部自動で付けるタグ（東京・us-east-1 で同じもの）
locals {
  default_tags = {
    project      = "yumeguri"
    env          = "staging"
    "managed-by" = "terraform"
  }
}
provider "aws" {
  region = "ap-northeast-1"

  # staging のアカウント以外では、plan・apply が止まる
  allowed_account_ids = [var.account_id]

  # このプロバイダーで作るものに、全部自動でタグを付ける
  default_tags {
    tags = local.default_tags
  }
}

# CloudFront の証明書は us-east-1 で作る決まりなので、us-east-1 用のプロバイダーを別名で足す（S1-16）
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.default_tags
  }
}

# API のトークンは、環境変数 CLOUDFLARE_API_TOKEN から読む（ファイルに書かない。infra/terraform/README.md）
provider "cloudflare" {}

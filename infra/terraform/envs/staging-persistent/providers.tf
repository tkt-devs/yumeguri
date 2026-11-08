# staging の「ずっと残す層」のプロバイダー（envs/staging と同じ設定）
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

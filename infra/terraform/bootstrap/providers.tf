provider "aws" {
  region = "ap-northeast-1"

  # このアカウント以外では、plan・apply が止まる
  allowed_account_ids = [var.account_id]

  # このプロバイダーで作るものに、全部自動でタグを付ける（費用を環境ごとに見分けるため）
  default_tags {
    tags = {
      project      = "yumeguri"
      env          = var.env
      "managed-by" = "terraform"
    }
  }
}

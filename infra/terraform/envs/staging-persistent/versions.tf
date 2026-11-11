# Terraform と AWS プロバイダーの版を固定する（手元・CI で同じ動きにするため）
# Terraform の版は、リポジトリのいちばん上の mise.toml と同じ範囲にする
# プロバイダーは版をちょうどに固定する（上げるのは Dependabot の PR）。中身の確認用の値は .terraform.lock.hcl に記録される（コミットする）
terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
    # DNS・ゾーンの設定・ルール（S1-16。ADR-024）
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.1"
    }
    # 秘密のヘッダーの値を作る（S1-16）
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

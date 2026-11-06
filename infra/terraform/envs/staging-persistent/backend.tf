# ずっと残す層の state。使うときだけの層（envs/staging）とは、記録を分ける（ADR-022）
terraform {
  backend "s3" {
    bucket       = "yumeguri-tfstate-staging"
    key          = "envs/staging-persistent/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

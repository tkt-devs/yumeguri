# staging の state は、bootstrap で作ったバケットに置く
# use_lockfile：同時に2人が apply して記録が壊れないように、S3 にロックのファイルを置く
# （DynamoDB の表を使う昔の方法は、非推奨になった）
terraform {
  backend "s3" {
    bucket       = "yumeguri-tfstate-staging"
    key          = "envs/staging/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

# bootstrap 自身の state も、作ったバケットに置く（Mac が壊れても残るように）
# バケットの名前などは、環境ごとのファイル（staging.s3.tfbackend）から渡す
# 最初の1回だけは、バケットがまだないので、backend_override.tf で Mac に置いて作る（README.md）
terraform {
  backend "s3" {}
}

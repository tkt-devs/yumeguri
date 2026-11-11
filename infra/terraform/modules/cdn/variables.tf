variable "name" {
  description = "作るものの名前（例：yumeguri-staging-img）"
  type        = string
}

variable "hostname" {
  description = "配信に使うホスト名（例：img-stg.sento-stamprally.com）"
  type        = string
}

variable "bucket_regional_domain_name" {
  description = "公開用サムネイルのバケットのドメイン名（リージョンつき）"
  type        = string
}

variable "certificate_arn" {
  description = "us-east-1 の ACM の証明書の ARN"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare のゾーンの ID"
  type        = string
}

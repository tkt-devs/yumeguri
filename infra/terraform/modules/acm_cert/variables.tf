variable "domain_name" {
  description = "証明書のドメイン名（例：api-stg.sento-stamprally.com）"
  type        = string
}

variable "zone_id" {
  description = "検証用のレコードを作る Cloudflare のゾーンの ID"
  type        = string
}

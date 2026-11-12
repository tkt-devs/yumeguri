variable "zone_id" {
  description = "Cloudflare のゾーンの ID"
  type        = string
}

variable "api_hostname" {
  description = "API のホスト名（例：api-stg.sento-stamprally.com）"
  type        = string
}

variable "header_name" {
  description = "Cloudflare が付ける秘密のヘッダーの名前（cf- で始まる名前は使えない）"
  type        = string
  default     = "x-origin-verify"
}

variable "secret_prefix" {
  description = "Secrets Manager の名前の頭（例：yumeguri/staging）。名前は <頭>/origin-header になる"
  type        = string
}

variable "webhook_path_prefix" {
  description = "WAF のマネージドルールから外す Webhook のパス"
  type        = string
  default     = "/v1/webhooks/"
}

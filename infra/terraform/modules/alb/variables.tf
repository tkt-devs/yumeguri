variable "name" {
  description = "作るものの名前の頭（例：yumeguri-staging）"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "ALB を置くサブネット（公開。2つの AZ）"
  type        = list(string)
}

variable "security_group_id" {
  description = "ALB に付ける門番（network の alb）"
  type        = string
}

variable "target_port" {
  description = "API のコンテナのポート"
  type        = number
  default     = 3001
}

variable "certificate_arn" {
  description = "HTTPS のリスナーに付ける ACM の証明書（東京リージョン）"
  type        = string
}

variable "origin_header_name" {
  description = "Cloudflare が付ける秘密のヘッダーの名前"
  type        = string
}

variable "origin_header_value" {
  description = "秘密のヘッダーの値（Secrets Manager から読む）"
  type        = string
  sensitive   = true
}

variable "access_log_bucket" {
  description = "アクセスログを置く S3 のバケット（SSE-S3 で暗号化したもの）"
  type        = string
}

variable "access_log_prefix" {
  description = "バケットの中の置き場所（バケットポリシーの許可と同じ値。envs/staging-persistent の出力）"
  type        = string
}

variable "name" {
  description = "バケットの名前の頭に付ける文字（例：yumeguri-staging）。S3 のバケットの名前は世界で1つだけなので、環境ごとに変える"
  type        = string
}

variable "upload_origins" {
  description = "ブラウザから非公開のバケットへ直接アップロードしてよい Web の URL（CORS。S3-03 で使う）"
  type        = list(string)
}

variable "generated_prefixes" {
  description = "非公開のバケットの中で、作ってから7日で消す場所（ジョブが作るファイル）"
  type        = list(string)
  default     = ["exports/", "reports/"]
}

variable "log_retention_days" {
  description = "ログ用のバケットのファイルを残す日数"
  type        = number
  default     = 90
}

variable "cloudfront_distribution_arns" {
  description = "公開用サムネイルのバケットを読んでよい CloudFront のディストリビューションの ARN（OAC）"
  type        = list(string)
  default     = []
}

variable "alb_log_prefix" {
  description = "ログ用のバケットの中で、ALB のアクセスログを置く場所（null なら、ALB に書く許可を出さない）"
  type        = string
  default     = null
}

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

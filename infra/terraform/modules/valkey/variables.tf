variable "name" {
  description = "作るものの名前（例：yumeguri-staging）"
  type        = string
}

variable "secret_prefix" {
  description = "シークレットの名前の頭（例：yumeguri/staging）"
  type        = string
}

variable "subnet_ids" {
  description = "置いてよいサブネット（非公開のサブネット）"
  type        = list(string)
}

variable "security_group_id" {
  description = "付ける門番（network の valkey）"
  type        = string
}

variable "engine_version" {
  description = "Valkey の版（ADR-012。ローカルの docker-compose.yml と同じ）"
  type        = string
  default     = "9.1"
}

variable "node_type" {
  description = "ノードの大きさ（ADR-012）"
  type        = string
  default     = "cache.t4g.micro"
}

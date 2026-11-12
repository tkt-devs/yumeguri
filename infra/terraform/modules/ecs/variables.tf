variable "name" {
  description = "作るものの名前の頭（例：yumeguri-staging）"
  type        = string
}

variable "private_subnet_ids" {
  description = "タスクを置くサブネット（非公開）"
  type        = list(string)
}

variable "api_security_group_id" {
  type = string
}

variable "worker_security_group_id" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "api_task_role_arn" {
  type = string
}

variable "worker_task_role_arn" {
  type = string
}

variable "api_image" {
  description = "API のイメージ（<ECR の URL>:<タグ>）"
  type        = string
}

variable "worker_image" {
  description = "ワーカーのイメージ（<ECR の URL>:<タグ>）"
  type        = string
}

variable "api_port" {
  type    = number
  default = 3001
}

variable "api_environment" {
  description = "API に渡す、見られても困らない環境変数"
  type        = map(string)
}

variable "api_secrets" {
  description = "API に渡す、シークレットからの環境変数（名前 → Secrets Manager の ARN。JSON の中の1つのキーなら <ARN>:<キー>::）"
  type        = map(string)
}

variable "worker_environment" {
  description = "ワーカーに渡す、見られても困らない環境変数"
  type        = map(string)
}

variable "api_target_group_arn" {
  description = "API のタスクを登録する ALB のターゲットグループ"
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "db_tasks_image" {
  description = "DB の準備用のイメージ（<ECR の URL>:<タグ>。apps/api/Dockerfile の db-tasks）"
  type        = string
}

variable "db_tasks_execution_role_arn" {
  description = "DB の準備用の単発のタスクのタスク実行ロール（管理者のパスワードを読める）"
  type        = string
}

variable "db_tasks" {
  description = "DB の準備用の単発のタスク（キー → command・メモリ・環境変数・シークレットからの環境変数）"
  type = map(object({
    command     = list(string)
    memory      = number
    environment = map(string)
    secrets     = map(string)
  }))
}

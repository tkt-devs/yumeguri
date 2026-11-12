variable "name" {
  description = "ロールの名前の頭（例：yumeguri-staging）"
  type        = string
}

variable "ecr_repository_arns" {
  description = "イメージを取ってきてよい ECR のリポジトリ"
  type        = list(string)
}

variable "log_group_arns" {
  description = "ログを書いてよいロググループ"
  type        = list(string)
}

variable "startup_secret_arns" {
  description = "タスクの起動のときに読んで、環境変数として渡すシークレット（タスク実行ロールが読む）"
  type        = list(string)
}

variable "private_bucket_arn" {
  description = "非公開のバケット（アップロードされた元のファイル）"
  type        = string
}

variable "public_bucket_arn" {
  description = "公開用のサムネイルのバケット"
  type        = string
}

variable "queue_arns" {
  description = "ジョブのキュー（jobs-default・jobs-heavy）"
  type        = list(string)
}

variable "api_runtime_secret_arns" {
  description = "API が動いている間に読み直すシークレット（QR の署名の鍵。ADR-015）"
  type        = list(string)
}

variable "worker_metric_namespace" {
  description = "ワーカーが CloudWatch に送ってよいメトリクスの名前空間"
  type        = string
  default     = "yumeguri/worker"
}

variable "db_tasks_ecr_repository_arn" {
  description = "DB の準備用のイメージ（yumeguri-db-tasks）のリポジトリ"
  type        = string
}

variable "db_tasks_log_group_arn" {
  description = "DB の準備用の単発のタスクのロググループ"
  type        = string
}

variable "db_tasks_secret_arns" {
  description = "DB の準備用の単発のタスクが読むシークレット（管理者と、3人のユーザーのパスワード）"
  type        = list(string)
}

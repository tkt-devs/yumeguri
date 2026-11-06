variable "name" {
  description = "作るものの名前（例：yumeguri-staging）"
  type        = string
}

variable "secret_prefix" {
  description = "シークレットの名前の頭（例：yumeguri/staging）"
  type        = string
}

variable "subnet_ids" {
  description = "RDS を置いてよいサブネット（非公開のサブネット。2つの AZ。ADR-019）"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS に付ける門番（network の rds）"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL の版（ADR-011）。大きな版だけを書き、小さな版は AWS に自動で上げさせる"
  type        = string
  default     = "18"
}

variable "instance_class" {
  description = "インスタンスの大きさ（ADR-011）"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "ディスクの大きさ（GB）"
  type        = number
  default     = 20
}

variable "backup_retention_days" {
  description = "自動のバックアップを残す日数（指定した時刻に戻せる範囲）"
  type        = number
  default     = 7
}

variable "db_users" {
  description = "アプリが使う DB のユーザー（ローカルの docker/postgres/init/01-roles.sql と同じ）。パスワードだけをここで作り、ユーザーそのものは RDS の中で SQL で作る（docs/runbook/db-users.md）"
  type        = set(string)
  default     = ["yumeguri_migrator", "yumeguri_app", "yumeguri_worker"]
}

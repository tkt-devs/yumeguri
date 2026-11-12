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

variable "ca_cert_identifier" {
  description = "RDS の証明書を発行する CA。prisma_ca_path のファイルと同じ CA にする"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

variable "prisma_ca_path" {
  description = "イメージの中の、ca_cert_identifier の CA だけが入ったファイルの場所（Prisma の CLI 用の URL の sslcert に入れる。apps/api/Dockerfile）"
  type        = string
  default     = "/certs/rds-ca-prisma.pem"
}

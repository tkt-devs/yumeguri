# RDS for PostgreSQL（ADR-011・ADR-019）

# RDS を置いてよいサブネット。Single-AZ でも、2つの AZ にまたがるように作る（あとで Multi-AZ にしやすい）
resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# 設定（パラメータグループ）。大きな版ごとに作る
resource "aws_db_parameter_group" "this" {
  # 作り直すとき（大きな版を上げるとき）は、新しいものを先に作るので、名前の後ろを AWS に付けさせる
  name_prefix = "${var.name}-postgres${var.engine_version}-"
  family      = "postgres${var.engine_version}"

  # 暗号化していない接続（SSL なし）を断る
  # （PostgreSQL 15 以降の RDS は初めから 1 だが、決めたことをコードに残す）
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = "yumeguri"
  username = "yumeguri_admin"
  # 管理者のパスワードは RDS が作って、Secrets Manager に置く。Terraform のコードにも state にも入らない
  manage_master_user_password = true

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  multi_az               = false # ADR-019
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # 使うたびに作って消す（ADR-022）。staging は消すときにスナップショットを取らない（毎回シードで作る）
  # production は S4-01b で、消す前に最後のスナップショットを取るようにする
  deletion_protection = false
  skip_final_snapshot = true

  # 設定の変更を、次のメンテナンスの時間まで待たずに、すぐ反映する
  apply_immediately = true
}

# ---- アプリ用の DB のユーザーのパスワード ----
# ephemeral：その場で作るだけで、state に残らない値
# secret_string_wo：Secrets Manager に「書き込むだけ」で、state に残さない
ephemeral "aws_secretsmanager_random_password" "db_user" {
  for_each = var.db_users

  password_length = 32
  # 記号を使わない（接続の URL（postgresql://user:password@host/db）にそのまま入れられるように）
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret" "db_user" {
  for_each = var.db_users

  name        = "${var.secret_prefix}/db/${each.key}"
  description = "RDS のユーザー ${each.key} のパスワード"
  # 使うたびに作って消すので、消したらすぐ消す（初めの値だと 7〜30 日残り、同じ名前で作り直せない）
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_user" {
  for_each = var.db_users

  secret_id = aws_secretsmanager_secret.db_user[each.key].id
  secret_string_wo = jsonencode({
    username = each.key
    password = ephemeral.aws_secretsmanager_random_password.db_user[each.key].random_password
  })
  # この番号を変えたときだけ、新しいパスワードを書き込む（変えなければ、plan のたびに書き換えない）
  secret_string_wo_version = 1
}

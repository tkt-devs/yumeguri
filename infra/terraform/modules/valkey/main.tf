# ElastiCache for Valkey（ADR-012）：ノード型・1台・クラスターモードなし・通信の暗号化（TLS）あり

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# ---- 接続するときの合言葉（AUTH トークン）----
# RDS の DB のユーザーと同じく、state に残さずに作る。流れは次の3つ：
# 1. その場で作る（ephemeral。state に残らない）→ Secrets Manager に書き込む（_wo。state に残らない）
# 2. Secrets Manager から読み直す（ephemeral）
# 3. 読み直した値を Valkey に渡す
# 2 を挟むので、Valkey だけが作り直されても、いつも Secrets Manager と同じ合言葉になる
ephemeral "aws_secretsmanager_random_password" "auth" {
  password_length = 32
  # Valkey の AUTH トークンに使えない記号（@ " / など）を避けるため、記号を使わない
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret" "auth" {
  name        = "${var.secret_prefix}/valkey-auth"
  description = "ElastiCache（Valkey）の AUTH トークン"
  # 使うたびに作って消すので、消したらすぐ消す
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id                = aws_secretsmanager_secret.auth.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.auth.random_password
  secret_string_wo_version = 1
}

# 最初の apply では、書き込む前は version_id が分からないので、Terraform は読むのを apply の中まで待つ
ephemeral "aws_secretsmanager_secret_version" "auth" {
  secret_id  = aws_secretsmanager_secret.auth.id
  version_id = aws_secretsmanager_secret_version.auth.version_id
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "yumeguri ${var.name}"

  # 設定（パラメータグループ）は、版の初めのもの（default.valkey9）を使う。指定しなければ AWS が選ぶ
  engine         = "valkey"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  # 1台だけ（予備なし）。止まったら、作り直すまで使えない（ADR-012）
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]

  # 通信の暗号化（TLS）と、保存の暗号化
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  # Secrets Manager から読み直した合言葉を「書き込むだけ」で渡す（state に残らない）
  # 作るときと、番号を変えたときだけ送る。合言葉を変えるときは、上の secret_string_wo_version と一緒に上げる
  auth_token_wo         = ephemeral.aws_secretsmanager_secret_version.auth.secret_string
  auth_token_wo_version = 1

  # 中身は短い値だけ（なくなっても困らない）なので、スナップショットを取らない
  snapshot_retention_limit = 0

  apply_immediately = true
}

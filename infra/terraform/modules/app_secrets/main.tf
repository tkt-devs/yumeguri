# 外部サービスのシークレットと署名用の鍵の「入れ物」（ADR-015）
# 値（secret_string）は Terraform に書かない。書くと state のファイルに平文で残るため
# 値は、作った後に `aws secretsmanager put-secret-value` か管理画面で入れる（docs/runbook/secrets.md）

resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name        = "${var.prefix}/${each.key}"
  description = each.value
  # 消しても 30 日は戻せる（Secrets Manager の初めの値）。ずっと残す層なので、間違って消したときに備える
  recovery_window_in_days = 30
}

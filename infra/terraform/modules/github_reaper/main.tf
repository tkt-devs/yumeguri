# 消し忘れの安全網：毎晩、GitHub Actions が使うときだけの層を消すためのロール（S1-19・ADR-027）
# - GitHub の Environment「staging-reaper」のジョブからだけ引き受けられる（CD や PR のジョブからは使えない）
# - 読むのは全部（terraform が state と AWS を見比べるため）。消せるのは、使うときだけの層の
#   お金のかかるもの（ECS・ALB・RDS・Valkey・タスクのロール・シークレット）だけ。名前の頭で絞る
# - 作ることはできない（Create・Put・Run がない）

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "arn:${data.aws_partition.current.partition}"
  in_region  = "${local.region}:${local.account_id}"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub が「このリポジトリの、この Environment」と完全に一致するときだけ
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }
  }
}

resource "aws_iam_role" "reaper" {
  name                 = "${var.name}-github-reaper"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

# 読むだけの権限は、AWS が用意したもの（ReadOnlyAccess）を使う。terraform の refresh で、
# どの種類のリソースを読むかが変わっても、ここを直さなくてよい
resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.reaper.name
  policy_arn = "${local.prefix}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "reaper" {
  # terraform の state（使うときだけの層は読み書き。ずっと残す層は読むだけ）
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = ["${local.prefix}:s3:::${var.state_bucket}"]
  }
  statement {
    sid     = "StateReadWrite"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${local.prefix}:s3:::${var.state_bucket}/${var.state_key}",
      "${local.prefix}:s3:::${var.state_bucket}/${var.state_key}.tflock",
    ]
  }
  statement {
    sid       = "PersistentStateRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.prefix}:s3:::${var.state_bucket}/${var.persistent_state_key}"]
  }

  # terraform が読む秘密の値（ReadOnlyAccess には、シークレットの中身を読む権限は入っていない）
  #   origin-header：envs/staging の data で読む。db/*・valkey-auth：消す前の refresh で、版を読む
  #   Google のログイン・セッションの鍵などは読ませない
  statement {
    sid     = "ReadSecretValues"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "${local.prefix}:secretsmanager:${local.in_region}:secret:${var.secret_prefix}/origin-header-*",
      "${local.prefix}:secretsmanager:${local.in_region}:secret:${var.secret_prefix}/db/*",
      "${local.prefix}:secretsmanager:${local.in_region}:secret:${var.secret_prefix}/valkey-auth-*",
    ]
  }

  # terraform は消すときも、DB のパスワードを作る部品（ephemeral の aws_secretsmanager_random_password）を開く。
  # ランダムな文字列を返すだけで、何も作らない・読まない（AWS がリソースを絞れない操作）
  statement {
    sid       = "RandomPassword"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  # ---- ここから下は消すだけ ----

  # ECS：サービスを0台にしてから消す・クラスターを消す（terraform の aws プロバイダーの消し方）
  statement {
    sid     = "EcsServices"
    actions = ["ecs:UpdateService", "ecs:DeleteService"]
    resources = [
      "${local.prefix}:ecs:${local.in_region}:service/${var.name}/*",
    ]
  }
  statement {
    sid       = "EcsCluster"
    actions   = ["ecs:DeleteCluster"]
    resources = ["${local.prefix}:ecs:${local.in_region}:cluster/${var.name}"]
  }
  # タスク定義の登録を外す（AWS がリソースを絞れない操作）
  statement {
    sid       = "EcsTaskDefinitions"
    actions   = ["ecs:DeregisterTaskDefinition", "ecs:DeleteTaskDefinitions"]
    resources = ["*"]
  }
  statement {
    sid       = "LogGroups"
    actions   = ["logs:DeleteLogGroup"]
    resources = ["${local.prefix}:logs:${local.in_region}:log-group:/ecs/${var.name}/*"]
  }

  # ALB（ロードバランサー・リスナー・ルール・ターゲットグループ）
  statement {
    sid = "LoadBalancer"
    actions = [
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
    ]
    resources = [
      "${local.prefix}:elasticloadbalancing:${local.in_region}:loadbalancer/app/${var.name}/*",
      "${local.prefix}:elasticloadbalancing:${local.in_region}:listener/app/${var.name}/*",
      "${local.prefix}:elasticloadbalancing:${local.in_region}:listener-rule/app/${var.name}/*",
      "${local.prefix}:elasticloadbalancing:${local.in_region}:targetgroup/${var.name}-*",
    ]
  }

  # ECS のタスクのロール（<name>-*-execution・<name>-*-task。modules/iam_ecs の名前の付け方）
  # デプロイ用・安全網のロール（<name>-github-*）や、NAT の EC2 のロールは、この形に入らない
  statement {
    sid = "TaskRoles"
    actions = [
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "${local.prefix}:iam::${local.account_id}:role/${var.name}-*-execution",
      "${local.prefix}:iam::${local.account_id}:role/${var.name}-*-task",
    ]
  }

  # RDS（インスタンス・パラメータグループ・サブネットグループ）
  statement {
    sid = "Rds"
    actions = [
      "rds:DeleteDBInstance",
      "rds:DeleteDBParameterGroup",
      "rds:DeleteDBSubnetGroup",
    ]
    resources = [
      "${local.prefix}:rds:${local.in_region}:db:${var.name}",
      "${local.prefix}:rds:${local.in_region}:pg:${var.name}-*",
      "${local.prefix}:rds:${local.in_region}:subgrp:${var.name}",
    ]
  }

  # ElastiCache（Valkey）
  statement {
    sid = "Valkey"
    actions = [
      "elasticache:DeleteReplicationGroup",
      "elasticache:DeleteCacheSubnetGroup",
    ]
    resources = [
      "${local.prefix}:elasticache:${local.in_region}:replicationgroup:${var.name}",
      "${local.prefix}:elasticache:${local.in_region}:cluster:${var.name}-*",
      "${local.prefix}:elasticache:${local.in_region}:subnetgroup:${var.name}",
    ]
  }

  # RDS のユーザー・Valkey の AUTH のシークレット（<secret_prefix>/db/*・<secret_prefix>/valkey-auth）
  # ずっと残す層のシークレット（origin-header など）は消さない
  statement {
    sid = "Secrets"
    # 版を消すとき、terraform の aws プロバイダーは版のラベルを外すことがある
    actions = ["secretsmanager:DeleteSecret", "secretsmanager:UpdateSecretVersionStage"]
    resources = [
      "${local.prefix}:secretsmanager:${local.in_region}:secret:${var.secret_prefix}/db/*",
      "${local.prefix}:secretsmanager:${local.in_region}:secret:${var.secret_prefix}/valkey-auth-*",
    ]
  }
}

resource "aws_iam_role_policy" "reaper" {
  name   = "reaper"
  role   = aws_iam_role.reaper.id
  policy = data.aws_iam_policy_document.reaper.json
}

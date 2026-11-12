# ECS のタスクが使う IAM ロール（AWS 構成図 v0.1 の IAM の表）
# 1つのロールには、使う操作と、使うリソースだけを許可する。リソースに "*" を使うのは、
# AWS がリソースを絞れない操作だけ（ECR のログイン・ECS Exec の通り道・メトリクスの送信）

data "aws_caller_identity" "current" {}

# ECS のタスクだけが引き受けられる。自分のアカウントの ECS からだけに絞る
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ---- タスク実行ロール：ECS が「タスクを起動するとき」に使う ----
# 2つ作る。中身の形は同じで、取ってくるイメージ・書くログ・読むシークレットだけが違う
# - ecs-execution：API・ワーカー
# - db-tasks-execution：DB の準備用の単発のタスク（S1-17）。管理者のパスワードを読めるのはこれだけ
#   （単発のタスクの中のアプリは AWS を使わないので、タスクロールは作らない）

locals {
  execution_roles = {
    ecs-execution = {
      ecr_repository_arns = var.ecr_repository_arns
      log_group_arns      = var.log_group_arns
      secret_arns         = var.startup_secret_arns
    }
    db-tasks-execution = {
      ecr_repository_arns = [var.db_tasks_ecr_repository_arn]
      log_group_arns      = [var.db_tasks_log_group_arn]
      secret_arns         = var.db_tasks_secret_arns
    }
  }
}

resource "aws_iam_role" "execution" {
  for_each = local.execution_roles

  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "execution" {
  for_each = local.execution_roles

  # ECR へのログイン（リソースを絞れない操作）
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 決められたリポジトリからだけ、イメージを取ってくる
  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = each.value.ecr_repository_arns
  }

  # 決められたロググループにだけ、ログを書く
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [for arn in each.value.log_group_arns : "${arn}:*"]
  }

  # 起動のときに渡すシークレット（DB のパスワードなど）だけを読む
  statement {
    sid       = "ReadStartupSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = each.value.secret_arns
  }
}

resource "aws_iam_role_policy" "execution" {
  for_each = local.execution_roles

  name   = each.key
  role   = aws_iam_role.execution[each.key].id
  policy = data.aws_iam_policy_document.execution[each.key].json
}

# ---- API のタスクロール：API のコンテナの中のアプリが使う ----

resource "aws_iam_role" "api" {
  name               = "${var.name}-api-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "api" {
  # アップロード用・ダウンロード用の署名つき URL を作る（非公開のバケットの uploads/ だけ）
  statement {
    sid       = "UploadsReadWrite"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${var.private_bucket_arn}/uploads/*"]
  }

  # ジョブを送る
  statement {
    sid       = "SendJobs"
    actions   = ["sqs:SendMessage"]
    resources = var.queue_arns
  }

  # QR の署名の鍵を、動いている間に読み直す（ADR-015）
  statement {
    sid       = "ReadRuntimeSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.api_runtime_secret_arns
  }

  # ECS Exec（コンテナの中に入る）の通り道。AWS がリソースを絞れない操作
  statement {
    sid = "EcsExec"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "api"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

# ---- ワーカーのタスクロール：ワーカーのコンテナの中のアプリが使う ----

resource "aws_iam_role" "worker" {
  name               = "${var.name}-worker-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "worker" {
  # ジョブを受け取る・消す・処理中の時間を延ばす
  statement {
    sid = "ConsumeJobs"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = var.queue_arns
  }

  # アップロードされた元のファイルを読む・消す
  statement {
    sid       = "UploadsReadDelete"
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["${var.private_bucket_arn}/uploads/*"]
  }

  # サムネイルを置く
  statement {
    sid       = "ThumbnailsWrite"
    actions   = ["s3:PutObject"]
    resources = ["${var.public_bucket_arn}/thumbnails/*"]
  }

  # メトリクスの送信（リソースを絞れない操作）。送ってよい名前空間を条件で絞る
  statement {
    sid       = "PutMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.worker_metric_namespace]
    }
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "worker"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

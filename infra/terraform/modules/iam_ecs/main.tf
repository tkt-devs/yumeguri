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

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "execution" {
  # ECR へのログイン（リソースを絞れない操作）
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # このアプリのリポジトリからだけ、イメージを取ってくる
  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = var.ecr_repository_arns
  }

  # このアプリのロググループにだけ、ログを書く
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [for arn in var.log_group_arns : "${arn}:*"]
  }

  # 起動のときに渡すシークレット（DB のパスワードなど）だけを読む
  statement {
    sid       = "ReadStartupSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.startup_secret_arns
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
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

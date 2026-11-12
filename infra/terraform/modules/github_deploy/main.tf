# GitHub Actions から AWS にデプロイするための入口（S1-17・ADR-026）
# - OIDC：GitHub が出す、その場限りの身分証（JWT）を AWS が確かめ、短い時間だけ使える鍵を渡す
#   → GitHub に AWS のアクセスキー（長く使える鍵）を置かない
# - デプロイ用のロール：決められたリポジトリの、決められたブランチからだけ引き受けられる

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  ecs_prefix = "arn:aws:ecs:${local.region}:${local.account_id}"
}

# ECS のクラスター・タスク定義・ロール・ロググループは、使うときだけの層（envs/staging）が作る。
# 名前を1つずつ並べず、modules/ecs・modules/iam_ecs の名前の付け方で絞る（部品が増えても、ここを直さなくてよい）
#   単発で動かしてよいタスク定義：<name>-db-*（db-bootstrap・db-migrate）
#   ECS に渡してよいロール：<name>-*-execution（タスク実行ロール）・<name>-*-task（タスクロール）
#   （デプロイ用のロール自身や、NAT の EC2 のロールは、この形に入らない）

# GitHub の身分証を出す先（GitHub の OIDC のプロバイダー）を、このアカウントに登録する
# アカウントに1つだけ作れる。aud（宛先）は sts.amazonaws.com（configure-aws-credentials が使う値）
# 証明書の指紋（thumbprint）は書かない：AWS が GitHub の証明書を自分で確かめる
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# 引き受けてよい条件：
# - aud が sts.amazonaws.com
# - sub が「このリポジトリの、このブランチ」と完全に一致する
#   （条件を付けないと、GitHub のほかの人のリポジトリからも引き受けられてしまう）
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  # 1回のデプロイ（ビルド・マイグレーション・入れ替え）が収まる長さ
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  # ECR へのログイン（リソースを絞れない操作）
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # このアプリのリポジトリにだけ、イメージを押し上げる・あるかを調べる
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }

  # 「いま staging に出すイメージのタグ」を書く・読む
  statement {
    sid       = "ImageTagParameter"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = [var.image_tag_parameter_arn]
  }

  # タスク定義を読む・新しい版を登録する（AWS がリソースを絞れない操作）
  statement {
    sid       = "TaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  # このクラスターのサービスだけを、調べる・入れ替える
  statement {
    sid       = "Services"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = ["${local.ecs_prefix}:service/${var.name}/*"]
  }

  # 単発のタスク（DB のユーザーの作成・マイグレーション）を、このクラスターでだけ動かす
  statement {
    sid       = "RunOneOffTasks"
    actions   = ["ecs:RunTask"]
    resources = ["${local.ecs_prefix}:task-definition/${var.name}-db-*:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["${local.ecs_prefix}:cluster/${var.name}"]
    }
  }

  # 動かした単発のタスクが終わったか、成功したかを調べる
  statement {
    sid       = "DescribeTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["${local.ecs_prefix}:task/${var.name}/*"]
  }

  # タスク定義の新しい版に、このアプリのロールだけを付けてよい（ECS のタスクに渡すときだけ）
  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.name}-*-execution",
      "arn:aws:iam::${local.account_id}:role/${var.name}-*-task",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # 単発のタスクが失敗したときに、ログを GitHub Actions に出す
  statement {
    sid       = "ReadOneOffTaskLogs"
    actions   = ["logs:GetLogEvents"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.name}/*:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# SQS のキュー（ADR-012）。API が送り、ワーカーが受け取る
# Celery にはキューを作らせない（services/worker/AGENTS.md）。ここで作ったものの URL を渡す

data "aws_caller_identity" "current" {}

# 失敗が続いたメッセージを置いておくキュー（DLQ）。原因を調べるために、14日残す
resource "aws_sqs_queue" "dlq" {
  for_each = var.queues

  name                      = "${each.key}-dlq"
  message_retention_seconds = 1209600 # 14日（いちばん長い値）
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "this" {
  for_each = var.queues

  name = each.key

  # 受け取ったメッセージを、ほかのワーカーから隠しておく秒数
  visibility_timeout_seconds = each.value
  # メッセージがないとき、最大20秒待ってから返す（長いポーリング。空の受信が減り、費用が下がる）
  receive_wait_time_seconds = 20
  # 4日（SQS の初めの値）。それまでに処理されなければ消える
  message_retention_seconds = 345600
  sqs_managed_sse_enabled   = true

  # 再処理ポリシー：max_receive_count 回受け取られても消えなければ、DLQ へ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

# DLQ に移してよいのは、対になるキューからだけ
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = var.queues

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this[each.key].arn]
  })
}

# ---- アクセスポリシー：このアカウント以外からの操作を、すべて断る ----
# （このアカウントの中で誰が使えるかは、IAM のロールで決める。S1-15）

locals {
  all_queues = merge(
    { for k, q in aws_sqs_queue.this : k => q },
    { for k, q in aws_sqs_queue.dlq : "${k}-dlq" => q },
  )
}

data "aws_iam_policy_document" "own_account_only" {
  for_each = local.all_queues

  statement {
    sid       = "DenyOtherAccounts"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [each.value.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    # AWS のサービス（EventBridge など）には aws:PrincipalAccount がないので、断る相手から外す
    # （このアカウントのキューに送ってよいかは、そのサービスの設定と IAM で別に決める）
    condition {
      test     = "Bool"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  for_each = local.all_queues

  queue_url = each.value.id
  policy    = data.aws_iam_policy_document.own_account_only[each.key].json
}

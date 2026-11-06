# S3 のバケット3つ（AWS 構成図 v0.1・ADR-024）
# - private：アップロードされた元のファイルと、ジョブが作るファイル（API・ワーカーが署名つき URL で読み書きする）
# - public ：公開用のサムネイル。名前は public だが、CloudFront からだけ読ませる（その許可は CloudFront を作るときに足す）
# - logs   ：ALB などのログ（ログを書き込む許可は、ALB を作るとき（S1-16）に足す）

locals {
  buckets = toset(["private", "public", "logs"])
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = "${var.name}-${each.key}"
}

# ---- 3つ共通 ----

# インターネットから読めるようにする設定を、すべて断る（public のバケットも。読むのは CloudFront だけ）
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACL を使わず、持ち主はいつもこのアカウントにする
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 暗号化（S3 の標準の鍵）。ALB のログは、この方式（SSE-S3）しか使えない
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---- private：バージョニング・CORS ----

# 上書き・削除しても、前の版を残す（間違って消したアップロードを戻せる）
resource "aws_s3_bucket_versioning" "private" {
  bucket = aws_s3_bucket.this["private"].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ブラウザから、署名つき URL で直接アップロード（PUT）・ダウンロード（GET）するための許可
# 許すのは、自分の Web の URL だけ
resource "aws_s3_bucket_cors_configuration" "private" {
  bucket = aws_s3_bucket.this["private"].id

  cors_rule {
    allowed_origins = var.upload_origins
    allowed_methods = ["PUT", "GET"]
    allowed_headers = ["content-type", "x-amz-*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ---- ライフサイクル（古いものを自動で消す） ----

resource "aws_s3_bucket_lifecycle_configuration" "private" {
  bucket = aws_s3_bucket.this["private"].id

  # ジョブが作るファイル（CSV など）は、作ってから7日で消す
  dynamic "rule" {
    for_each = var.generated_prefixes

    content {
      id     = "expire-${trimsuffix(rule.value, "/")}"
      status = "Enabled"

      filter {
        prefix = rule.value
      }

      expiration {
        days = 7
      }

      # バージョニングがあるので、上の「消す」は、古い版として残る。それも1日で消す
      noncurrent_version_expiration {
        noncurrent_days = 1
      }
    }
  }

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {}

    # 上書き・削除されて古くなった版は、30日で消す
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # 古い版がすべて消えて、削除の印だけが残ったものを消す
    expiration {
      expired_object_delete_marker = true
    }

    # 途中で止まったアップロードの断片は、7日で消す（見えないが、費用がかかる）
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # バージョニングを先に有効にする
  depends_on = [aws_s3_bucket_versioning.private]
}

resource "aws_s3_bucket_lifecycle_configuration" "public" {
  bucket = aws_s3_bucket.this["public"].id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.this["logs"].id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    # ログは、たまり続けると費用が増えるので、決めた日数で消す
    expiration {
      days = var.log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---- HTTPS だけ（3つ共通） ----

data "aws_iam_policy_document" "https_only" {
  for_each = aws_s3_bucket.this

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.https_only[each.key].json

  # パブリックアクセスのブロックを先に有効にする（逆だと、一瞬だけ設定がない時間ができる）
  depends_on = [aws_s3_bucket_public_access_block.this]
}

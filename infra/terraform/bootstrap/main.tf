# Terraform の state（Terraform が AWS に作ったものの記録）を置く S3 のバケット
# envs/<環境>/ の state と、bootstrap 自身の state がここに入る

resource "aws_s3_bucket" "tfstate" {
  bucket = "yumeguri-tfstate-${var.env}"

  # Terraform の操作の間違いで、記録ごと消さないようにする
  # （本当に消すときは、この行を外してから destroy する）
  lifecycle {
    prevent_destroy = true
  }
}

# 書き換えるたびに前の版を残す。state を壊しても、前の版に戻せる
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 暗号化（S3 の標準の鍵）。state には DB のアドレスなどが入る
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# インターネットから読めるようにする設定を、すべて断る
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACL を使わず、持ち主はいつもこのアカウントにする（AWS の今のおすすめ）
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 古い版は 90 日で消す（たまって費用が増えないように）
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    # 古い版がすべて消えて、削除の印（delete marker）だけが残ったものを消す
    # （use_lockfile のロックのファイルは、plan・apply のたびに作って消すので、印がたまる）
    expiration {
      expired_object_delete_marker = true
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # バージョニングを先に有効にする
  depends_on = [aws_s3_bucket_versioning.tfstate]
}

# HTTPS 以外の通信を断る（通信の途中で読まれないように）
data "aws_iam_policy_document" "tfstate" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]

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

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json

  # パブリックアクセスのブロックを先に入れる
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

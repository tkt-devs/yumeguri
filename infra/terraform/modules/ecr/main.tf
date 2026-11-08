# ECR：コンテナのイメージを置く場所（ずっと残す層。ADR-022）

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name = each.key
  # 同じタグで上書きできないようにする（タグ＝Git のコミット ID。どのコードが動いているかを確実にする）
  image_tag_mutability = "IMMUTABLE"

  # 押し上げたときに、既知の脆弱性がないかを調べる（基本のスキャン。無料）
  image_scanning_configuration {
    scan_on_push = true
  }

  # 暗号化（ECR の標準の鍵）
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# 古いイメージを自動で消す（たまると保存の費用がかかる）
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "タグのないイメージは1日で消す"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "タグのあるイメージは、新しい ${var.keep_images} 個だけ残す"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

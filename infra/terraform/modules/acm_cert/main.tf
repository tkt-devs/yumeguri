# ACM の証明書を1枚作り、DNS で「このドメインの持ち主です」と証明する（S1-16）
# 検証用のレコードは、DNS を管理している Cloudflare に作る
# リージョンは、呼ぶ側が渡す aws のプロバイダーで決まる（ALB 用は東京、CloudFront 用は us-east-1）

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # 作り直すときは、新しい証明書を先に作ってから古いものを消す（使っている証明書は消せないため）
  lifecycle {
    create_before_destroy = true
  }
}

# ACM が指定する CNAME（_xxxx.<ドメイン> → _yyyy.acm-validations.aws）を Cloudflare に作る
resource "cloudflare_dns_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }

  zone_id = var.zone_id
  # ACM の値は最後に「.」が付いているので外す
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 300
  # 検証用のレコードは、Cloudflare を通さない（灰色の雲）。通すと ACM が値を読めない
  proxied = false
  comment = "ACM validation (Terraform)"
}

# 検証が終わる（証明書が「発行済み」になる）まで待つ
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in cloudflare_dns_record.validation : r.name]
}

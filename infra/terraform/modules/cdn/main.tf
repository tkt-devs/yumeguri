# 画像の配信（S1-16・ADR-024）：CloudFront が、公開用サムネイルのバケットから読んで配る
# バケットは非公開のまま。OAC（Origin Access Control）で、CloudFront だけが読めるようにする
# （読む許可のバケットポリシーは modules/buckets にある。ここで作るディストリビューションの ARN を渡す）

# CloudFront が S3 に「自分です」と署名して読みに行くための設定
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = var.name
  description                       = "CloudFront to the public thumbnail bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS が用意したキャッシュの方針（クエリ・Cookie を無視し、長く覚える。画像向け）
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = var.name
  aliases         = [var.hostname]
  is_ipv6_enabled = true
  http_version    = "http2and3"
  # 日本を含む地域だけ（いちばん安い PriceClass_100 には日本が入らない）
  price_class = "PriceClass_200"

  origin {
    origin_id                = "s3-public"
    domain_name              = var.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-public"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 証明書は us-east-1 のもの（CloudFront は us-east-1 の証明書しか使えない）
  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# img. を CloudFront に向ける。Cloudflare のプロキシは使わない（灰色の雲。CDN を二重にしない）
resource "cloudflare_dns_record" "this" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = aws_cloudfront_distribution.this.domain_name
  ttl     = 300
  proxied = false
  comment = "CloudFront (Terraform)"
}

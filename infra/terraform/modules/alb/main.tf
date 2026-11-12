# ALB：Cloudflare からのリクエストを受けて、API のタスクに振り分ける入口
# HTTPS（443）だけ。Cloudflare が付ける秘密のヘッダーがないリクエストは 403 にする（ADR-013・S1-16）

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  # 形の崩れたヘッダーのリクエストを捨てる（リクエストの密輸のような攻撃を防ぐ）
  drop_invalid_header_fields = true

  # アクセスログ（だれが・いつ・どのパスに来て、どう答えたか）を S3 に置く
  access_logs {
    enabled = true
    bucket  = var.access_log_bucket
    prefix  = var.access_log_prefix
  }
}

# API のタスクの一覧（ECS が、タスクの IP をここに登録する）
resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate は、タスクの IP で登録する
  protocol    = "HTTP"
  port        = var.target_port

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # タスクを入れ替えるとき、古いタスクへの新しいリクエストを止めてから、30秒待って外す
  # （初めの値は300秒。staging では待ち時間を短くする）
  deregistration_delay = 30
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  # TLS 1.2・1.3 だけ。量子コンピューターへの備え（PQ）つき。管理画面で作るときの初めの値と同じ
  # （Terraform・CLI で省くと、古い ELBSecurityPolicy-2016-08 になる）
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"

  # どのルールにも合わなければ 403（ALB の DNS 名に直接来たリクエストなど）
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "403"
      message_body = "Forbidden"
    }
  }
}

# Cloudflare が付けた秘密のヘッダーがあるときだけ、API に渡す
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = var.origin_header_name
      values           = [var.origin_header_value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

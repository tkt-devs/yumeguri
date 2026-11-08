# ALB：インターネットからのリクエストを受けて、API のタスクに振り分ける入口
# 今は HTTP（80）だけ。HTTPS（443）・証明書・Cloudflare の秘密のヘッダーは S1-16 で足す

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  # 形の崩れたヘッダーのリクエストを捨てる（リクエストの密輸のような攻撃を防ぐ）
  drop_invalid_header_fields = true
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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

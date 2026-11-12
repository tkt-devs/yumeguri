# ECS（Fargate・ARM。ADR-002）：クラスター・ロググループ・タスク定義・サービス

data "aws_region" "current" {}

resource "aws_ecs_cluster" "this" {
  name = var.name

  # Container Insights（詳しいメトリクス）は使わない（費用がかかる。v0.1 は CloudWatch の標準のメトリクスで足りる）
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# ---- ログ（API・ワーカー・DB の準備用の単発のタスク）。30日で消す ----

resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(["api", "worker", "db-tasks"])

  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

locals {
  # 環境変数の map を、タスク定義の形（[{ name, value }]）にする
  api_environment    = [for k, v in var.api_environment : { name = k, value = v }]
  api_secrets        = [for k, v in var.api_secrets : { name = k, valueFrom = v }]
  worker_environment = [for k, v in var.worker_environment : { name = k, value = v }]

  log_options = {
    for k, g in aws_cloudwatch_log_group.this : k => {
      "awslogs-group"         = g.name
      "awslogs-region"        = data.aws_region.current.region
      "awslogs-stream-prefix" = k
    }
  }
}

# ---- タスク定義：どのイメージを、どの設定で、どれだけの CPU・メモリで動かすか ----

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # 最小から始める（0.25 vCPU・0.5 GB）
  cpu                = 256
  memory             = 512
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.api_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name         = "api"
      image        = var.api_image
      essential    = true
      portMappings = [{ containerPort = var.api_port, protocol = "tcp" }]
      environment  = local.api_environment
      secrets      = local.api_secrets
      # ECS Exec で中に入るため（SSM のエージェントが動く）
      linuxParameters = { initProcessEnabled = true }
      logConfiguration = {
        logDriver = "awslogs"
        options   = local.log_options["api"]
      }
      # コンテナのヘルスチェック（Dockerfile の HEALTHCHECK と同じ中身。ECS は Dockerfile のものを使わない）
      healthCheck = {
        command     = ["CMD", "node", "-e", "fetch('http://127.0.0.1:${var.api_port}/healthz').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    },
  ])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.worker_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  # ヘルスチェックは書かない（Celery のワーカーには HTTP の窓口がない。services/worker/Dockerfile）
  container_definitions = jsonencode([
    {
      name        = "worker"
      image       = var.worker_image
      essential   = true
      environment = local.worker_environment
      logConfiguration = {
        logDriver = "awslogs"
        options   = local.log_options["worker"]
      }
    },
  ])
}

# ---- DB の準備用の単発のタスク（S1-17）：CD（infra/scripts/deploy-staging.sh）が、デプロイの前に1回ずつ動かす ----
# イメージは apps/api/Dockerfile の db-tasks。サービスにはしない（動かして、終わったら止まる）
# どのサブネット・門番で動かすかは、CD が api のサービスの設定をそのまま使う
# （RDS の門番が、api からの 5432 を通すため）
# family は <name>-<キー>、コンテナの名前・ログの頭はキーと同じ（CD がこの形で探す）

resource "aws_ecs_task_definition" "db_task" {
  for_each = var.db_tasks

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = each.value.memory
  execution_role_arn       = var.db_tasks_execution_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name        = each.key
      image       = var.db_tasks_image
      essential   = true
      command     = each.value.command
      environment = [for k, v in each.value.environment : { name = k, value = v }]
      secrets     = [for k, v in each.value.secrets : { name = k, valueFrom = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options["db-tasks"], { "awslogs-stream-prefix" = each.key })
      }
    },
  ])
}

# ---- サービス：決めた数のタスクを、ずっと動かしておく ----

resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1 # staging は1つ
  launch_type     = "FARGATE"

  # ECS Exec で、コンテナの中に入れるようにする
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.api_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.api_target_group_arn
    container_name   = "api"
    container_port   = var.api_port
  }

  # 起動してから、ALB のヘルスチェックの失敗を数え始めるまでの猶予
  health_check_grace_period_seconds = 30

  # 新しいタスクが起動できなかったら、前のタスク定義に自動で戻す
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

resource "aws_ecs_service" "worker" {
  name            = "worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.worker_security_group_id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

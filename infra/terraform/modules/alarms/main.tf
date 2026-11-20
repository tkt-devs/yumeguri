# 最初のアラーム（S1-20・ADR-017）。鳴ったら、ずっと残す層の SNS のトピック（メール）に知らせる
# 使うときだけの層に置く（ALB・ECS と一緒に作って消す。消し忘れると、データがなくて鳴り続けるため）

locals {
  actions = [var.alarm_topic_arn]
}

# ALB の 5xx の割合：API が返した 5xx（ターゲット）と、ALB 自身が返した 5xx（API に届かなかった）を合わせて、
# 全部のリクエストの何 % か。5 分で 5 % を超えたら鳴らす
resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${var.name}-alb-5xx-rate"
  alarm_description   = "API の 5xx の割合が ${var.alb_5xx_rate_threshold} % を超えた（5 分間）。Sentry と CloudWatch Logs で原因を見る"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_rate_threshold
  evaluation_periods  = 1
  # リクエストがない時間は、データがない。そのときは鳴らさない
  treat_missing_data = "notBreaching"
  alarm_actions      = local.actions
  ok_actions         = local.actions

  metric_query {
    id          = "rate"
    expression  = "100 * (FILL(target5xx, 0) + FILL(elb5xx, 0)) / requests"
    label       = "5xx の割合（%）"
    return_data = true
  }

  metric_query {
    id = "target5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = var.api_target_group_arn_suffix
      }
    }
  }

  metric_query {
    id = "elb5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }
}

# ECS のタスクの数が 0：Container Insights は使わない（費用がかかる）ので、
# タスクが動いている間だけ 1 分ごとに届く CPU のメトリクスの「数」（SampleCount）で見る。
# 2 分続けて 1 つも届かなければ（タスクが 0）鳴らす。データがないことも「鳴らす」とみなす
resource "aws_cloudwatch_metric_alarm" "no_running_tasks" {
  for_each = toset(var.service_names)

  alarm_name          = "${var.name}-${each.key}-no-running-tasks"
  alarm_description   = "${each.key} のタスクが 1 つも動いていない（2 分間）。ECS のサービスのイベントと、タスクの止まった理由を見る"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "SampleCount"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.key
  }
}

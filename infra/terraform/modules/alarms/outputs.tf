output "alarm_names" {
  description = "作ったアラームの名前（試しに鳴らすとき：aws cloudwatch set-alarm-state）"
  value = concat(
    [aws_cloudwatch_metric_alarm.alb_5xx_rate.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.no_running_tasks : a.alarm_name],
  )
}

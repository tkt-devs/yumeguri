variable "name" {
  description = "環境の名前（例：yumeguri-staging）。アラームの名前の頭"
  type        = string
}

variable "alarm_topic_arn" {
  description = "鳴ったとき・戻ったときに知らせる SNS のトピック（ずっと残す層）"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB の ARN の後ろの部分（app/<名前>/<ID>。CloudWatch のメトリクスの LoadBalancer）"
  type        = string
}

variable "api_target_group_arn_suffix" {
  description = "API のターゲットグループの ARN の後ろの部分（targetgroup/<名前>/<ID>）"
  type        = string
}

variable "alb_5xx_rate_threshold" {
  description = "5xx の割合（%）が、これを超えたら鳴らす"
  type        = number
  default     = 5
}

variable "cluster_name" {
  description = "ECS のクラスターの名前"
  type        = string
}

variable "service_names" {
  description = "タスクの数を見る ECS のサービス"
  type        = list(string)
}

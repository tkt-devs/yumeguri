variable "queues" {
  description = "キューの名前 → 可視性タイムアウト（秒）。ジョブの上限の時間より長くする（ローカルの docker/localstack/init/01-resources.sh と同じ値）"
  type        = map(number)
  default = {
    "jobs-default" = 120
    "jobs-heavy"   = 900
  }
}

variable "max_receive_count" {
  description = "この回数受け取られても消えなかった（＝失敗が続いた）メッセージを、DLQ に移す"
  type        = number
  default     = 3
}

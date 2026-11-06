output "queue_urls" {
  description = "キューの URL（API・ワーカーの SQS_QUEUE_URL_DEFAULT・SQS_QUEUE_URL_HEAVY に渡す。S1-15）"
  value       = { for k, q in aws_sqs_queue.this : k => q.id }
}

output "queue_arns" {
  description = "キューの ARN（IAM のロールで許可するときに使う。S1-15）"
  value       = { for k, q in aws_sqs_queue.this : k => q.arn }
}

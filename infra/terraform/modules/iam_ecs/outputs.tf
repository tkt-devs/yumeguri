# どのロールも、許可（ポリシー）を付け終わってから使う側に渡す
# （先にタスクが起動すると、権限がないままイメージを取りに行って失敗する）

output "execution_role_arn" {
  value      = aws_iam_role.execution["ecs-execution"].arn
  depends_on = [aws_iam_role_policy.execution]
}

output "api_task_role_arn" {
  value      = aws_iam_role.api.arn
  depends_on = [aws_iam_role_policy.api]
}

output "worker_task_role_arn" {
  value      = aws_iam_role.worker.arn
  depends_on = [aws_iam_role_policy.worker]
}

output "db_tasks_execution_role_arn" {
  value      = aws_iam_role.execution["db-tasks-execution"].arn
  depends_on = [aws_iam_role_policy.execution]
}

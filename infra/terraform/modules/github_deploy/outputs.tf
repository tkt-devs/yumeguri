output "role_arn" {
  description = "GitHub Actions が引き受けるロール（リポジトリのシークレット AWS_DEPLOY_ROLE_ARN に入れる）"
  value       = aws_iam_role.deploy.arn
  depends_on  = [aws_iam_role_policy.deploy]
}

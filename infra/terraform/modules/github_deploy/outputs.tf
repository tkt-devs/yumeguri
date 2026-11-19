output "role_arn" {
  description = "GitHub Actions が引き受けるロール（リポジトリのシークレット AWS_DEPLOY_ROLE_ARN に入れる）"
  value       = aws_iam_role.deploy.arn
  depends_on  = [aws_iam_role_policy.deploy]
}

output "oidc_provider_arn" {
  description = "GitHub の OIDC のプロバイダー（アカウントに1つだけ。安全網のロール（modules/github_reaper）も使う）"
  value       = aws_iam_openid_connect_provider.github.arn
}

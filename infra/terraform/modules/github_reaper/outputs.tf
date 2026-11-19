output "role_arn" {
  description = "安全網のジョブが引き受けるロール（Environment staging-reaper のシークレット AWS_REAPER_ROLE_ARN に入れる）"
  value       = aws_iam_role.reaper.arn
  depends_on  = [aws_iam_role_policy.reaper, aws_iam_role_policy_attachment.read_only]
}

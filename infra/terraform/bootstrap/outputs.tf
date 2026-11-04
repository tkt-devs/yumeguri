output "state_bucket" {
  description = "state を置くバケットの名前（apply のあとに表示して、確かめるため）"
  value       = aws_s3_bucket.tfstate.bucket
}

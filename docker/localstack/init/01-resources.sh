#!/bin/bash
# LocalStack の起動が終わるたびに、バケットとキューを作る（ADR-012・ADR-020）
set -euo pipefail

# 本番と同じ東京リージョンに作る
export AWS_DEFAULT_REGION=ap-northeast-1

# バケット：アップロードされた元のファイル（非公開）と、公開用のサムネイル
awslocal s3 mb s3://yumeguri-local-private
awslocal s3 mb s3://yumeguri-local-public

# キュー：3回続けて失敗したメッセージは、それぞれの DLQ に移す
for name in jobs-default jobs-heavy; do
  dlq_url=$(awslocal sqs create-queue --queue-name "${name}-dlq" --query QueueUrl --output text)
  dlq_arn=$(awslocal sqs get-queue-attributes --queue-url "${dlq_url}" \
    --attribute-names QueueArn --query Attributes.QueueArn --output text)

  cat > "/tmp/${name}-attributes.json" <<JSON
{ "RedrivePolicy": "{\"deadLetterTargetArn\":\"${dlq_arn}\",\"maxReceiveCount\":\"3\"}" }
JSON
  awslocal sqs create-queue --queue-name "${name}" --attributes "file:///tmp/${name}-attributes.json"
done

#!/bin/bash
# LocalStack の起動が終わるたびに、バケットとキューを作る（ADR-012・ADR-020）
set -euo pipefail

# 本番と同じ東京リージョンに作る
export AWS_DEFAULT_REGION=ap-northeast-1

# バケット：アップロードされた元のファイル（非公開）と、公開用のサムネイル
awslocal s3 mb s3://yumeguri-local-private
awslocal s3 mb s3://yumeguri-local-public

# キュー：3回続けて失敗したメッセージは、それぞれの DLQ に移す
# 可視性タイムアウト（受け取ったメッセージを、ほかのワーカーから隠しておく秒数）は、
# そのキューの一番長いジョブの上限より長くする（要件定義書 11.2・services/worker/app/celery_app.py）
#   jobs-default：ジョブの上限 60秒 → 120秒
#   jobs-heavy  ：ジョブの上限 10分 → 900秒（15分）
declare -A visibility_timeout=([jobs-default]=120 [jobs-heavy]=900)
# ReceiveMessageWaitTimeSeconds：メッセージがないとき、最大20秒待ってから返す（長いポーリング）
# 空の受信の回数が減り、費用と CPU を節約できる。Celery（kombu）は受け取るたびに自分の値を送るので、
# ワーカーの側も同じ20秒にしている（services/worker/app/celery_app.py の wait_time_seconds）

for name in jobs-default jobs-heavy; do
  dlq_url=$(awslocal sqs create-queue --queue-name "${name}-dlq" --query QueueUrl --output text)
  dlq_arn=$(awslocal sqs get-queue-attributes --queue-url "${dlq_url}" \
    --attribute-names QueueArn --query Attributes.QueueArn --output text)

  cat > "/tmp/${name}-attributes.json" <<JSON
{
  "RedrivePolicy": "{\"deadLetterTargetArn\":\"${dlq_arn}\",\"maxReceiveCount\":\"3\"}",
  "VisibilityTimeout": "${visibility_timeout[$name]}",
  "ReceiveMessageWaitTimeSeconds": "20"
}
JSON
  awslocal sqs create-queue --queue-name "${name}" --attributes "file:///tmp/${name}-attributes.json"
done

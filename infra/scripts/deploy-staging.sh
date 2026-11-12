#!/usr/bin/env bash
# staging の ECS を、新しいイメージ（タグ）に入れ替える（S1-17・ADR-026）
# CD（.github/workflows/cd.yml）が使う。手で動かすこともできる（デプロイ用の権限が要る）
#
#   使い方：infra/scripts/deploy-staging.sh <タグ>
#   要るもの：aws CLI・jq・AWS の認証情報
#
# 流れ：
#   1. staging が動いていなければ、タグを記録するだけで終わる（使うときだけの環境。ADR-022）
#   2. DB のユーザーを作る（db-bootstrap）→ マイグレーション（db-migrate）。どちらも単発のタスク。失敗したら止める
#   3. API・ワーカーのタスク定義を新しいイメージで登録し、サービスを入れ替えて、落ち着くまで待つ
#   4. 成功したら、タグを記録する（次に up したときも、このイメージで作られる）
set -euo pipefail

TAG="${1:?使い方：deploy-staging.sh <タグ>}"
NAME="${NAME:-yumeguri-staging}"
CLUSTER="${CLUSTER:-$NAME}"
TAG_PARAMETER="${TAG_PARAMETER:-/yumeguri/staging/image-tag}"
LOG_GROUP="/ecs/$NAME/db-tasks"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# 画面と、GitHub Actions の実行結果のまとめ（Summary）の両方に書く
note() {
  echo "$*"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$*" >>"$GITHUB_STEP_SUMMARY"
  fi
}

record_tag() {
  aws ssm put-parameter --name "$TAG_PARAMETER" --value "$TAG" --type String --overwrite >/dev/null
  note "- 動かすイメージのタグを \`$TAG\` に記録した（\`$TAG_PARAMETER\`）"
}

# タスク定義の新しい版を登録する。中身は今の版のまま、イメージのタグだけを変える
#   $1：今のタスク定義（family か ARN）  出力：新しい版の ARN
new_revision() {
  local file="$WORK_DIR/task-definition.json"
  aws ecs describe-task-definition --task-definition "$1" --query taskDefinition --output json |
    jq --arg tag "$TAG" '
      .containerDefinitions |= map(.image |= sub(":[^:/]+$"; ":" + $tag))
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
            .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)' >"$file"
  aws ecs register-task-definition --cli-input-json "file://$file" \
    --query taskDefinition.taskDefinitionArn --output text
}

# 単発のタスクを動かし、終わるまで待つ。失敗したら、ログを出して止める
#   $1：名前（db-bootstrap・db-migrate）。family は $NAME-$1、コンテナの名前・ログの頭も $1（modules/ecs）
run_once() {
  local name="$1" task_definition task stopped exit_code
  task_definition="$(new_revision "$NAME-$name")"

  # どのサブネット・門番で動かすかは、API のサービスと同じにする（RDS の門番が、api からの 5432 を通す）
  task="$(aws ecs run-task --cluster "$CLUSTER" --task-definition "$task_definition" \
    --launch-type FARGATE --network-configuration "$API_NETWORK" \
    --query 'tasks[0].taskArn' --output text)"
  if [ -z "$task" ] || [ "$task" = "None" ]; then
    echo "::error::$name のタスクを起動できなかった"
    exit 1
  fi
  echo "$name：タスクを起動した。終わるまで待つ"
  aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$task"

  # 終了コードと止まった理由を、1回で取る（タブで区切られる）
  stopped="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task" \
    --query 'tasks[0].[containers[0].exitCode, stoppedReason]' --output text)"
  exit_code="${stopped%%$'\t'*}"
  if [ "$exit_code" != "0" ]; then
    echo "::error::$name が失敗した（終了コード・理由：$stopped）"
    echo "---- $name のログ ----"
    aws logs get-log-events --log-group-name "$LOG_GROUP" \
      --log-stream-name "$name/$name/${task##*/}" --query 'events[].message' --output text || true
    exit 1
  fi
  note "- $name：成功"
}

# サービスを、今の版のイメージのタグだけを変えた新しい版に入れ替え始める。出力：新しい版の ARN
#   $1：サービスの名前  $2：今のタスク定義
start_rollout() {
  local service="$1" task_definition
  task_definition="$(new_revision "$2")"
  aws ecs update-service --cluster "$CLUSTER" --service "$service" \
    --task-definition "$task_definition" >/dev/null
  echo "$service：${task_definition##*/} に入れ替え始めた" >&2
  echo "$task_definition"
}

# 新しいタスクが起動できないと、ECS は前の版に自動で戻す（サーキットブレーカー）。
# そのときも「落ち着いた」になるので、新しい版で動いているかを確かめる
#   $1：サービスの名前  $2：動いているはずの版
check_running() {
  local running
  running="$(aws ecs describe-services --cluster "$CLUSTER" --services "$1" \
    --query 'services[0].taskDefinition' --output text)"
  if [ "$running" != "$2" ]; then
    echo "::error::$1 は新しい版で動いていない（前の版に戻った）：${running##*/}"
    exit 1
  fi
  note "- $1：\`${running##*/}\` で動いている"
}

# ---- 1. staging が動いているか。動いていれば、今のサービスの設定を1回で読んでおく ----
# 「クラスターがない」（ClusterNotFoundException）だけを「止まっている」とみなす。
# それ以外のエラー（権限がない・認証が切れた・混み合っている）は、デプロイの失敗として止める
# （止まっていると勘違いして、何も入れ替えずに成功にしないため）
if ! services="$(aws ecs describe-services --cluster "$CLUSTER" --services api worker --output json 2>"$WORK_DIR/error")"; then
  if grep -q ClusterNotFoundException "$WORK_DIR/error"; then
    services='{"services": []}'
  else
    cat "$WORK_DIR/error" >&2
    echo "::error::staging の状態を調べられなかった"
    exit 1
  fi
fi
service_field() { # $1：サービスの名前  $2：取り出す項目（jq の書き方）
  jq -c --arg name "$1" ".services[] | select(.serviceName == \$name and .status == \"ACTIVE\") | $2" <<<"$services"
}
api_current="$(service_field api '.taskDefinition' | tr -d '"')"
worker_current="$(service_field worker '.taskDefinition' | tr -d '"')"
if [ -z "$api_current" ] || [ -z "$worker_current" ]; then
  note "- staging は止まっている（使うときだけの環境）。イメージを押し上げ、タグを記録するだけにする"
  record_tag
  exit 0
fi
API_NETWORK="$(service_field api '.networkConfiguration')"

# ---- 2. DB の準備 ----
run_once db-bootstrap
run_once db-migrate

# ---- 3. API・ワーカーを入れ替え、落ち着くまで待つ ----
new_api="$(start_rollout api "$api_current")"
new_worker="$(start_rollout worker "$worker_current")"
echo "サービスが落ち着くまで待つ（最大 10 分）"
aws ecs wait services-stable --cluster "$CLUSTER" --services api worker
check_running api "$new_api"
check_running worker "$new_worker"

# ---- 4. 成功したら、タグを記録する ----
record_tag

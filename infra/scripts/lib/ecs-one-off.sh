# shellcheck shell=bash disable=SC2153 # NAME・CLUSTER・API_NETWORK は、source する側が決める
# ECS の単発のタスク（db-bootstrap・db-migrate・db-seed）を動かして、終わるまで待つ（S1-17・S1-19）
# deploy-staging.sh と staging.sh が、source して使う。単体では動かさない
#
# 使う前に決めておく変数：
#   CLUSTER     ECS のクラスターの名前
#   NAME        環境の名前（タスク定義の family・ロググループの頭。例：yumeguri-staging）
#   API_NETWORK どのサブネット・門番で動かすか（API のサービスの networkConfiguration の JSON）

# 画面と、GitHub Actions の実行結果のまとめ（Summary）の両方に書く
note() {
  echo "$*"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$*" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# API のサービスの networkConfiguration（JSON）を出す。サービスがなければ、空を出す
#   RDS の門番が、API の門番からの 5432 を通すので、単発のタスクも API と同じ門番で動かす
api_network() {
  # shellcheck disable=SC2016 # ` ` は JMESPath の文字列で、シェルの展開ではない
  aws ecs describe-services --cluster "$CLUSTER" --services api \
    --query 'services[?status==`ACTIVE`] | [0].networkConfiguration' --output json |
    sed 's/^null$//'
}

# 単発のタスクを動かし、終わるまで待つ。失敗したら、ログを出して止める
#   $1：名前（db-bootstrap など。コンテナの名前・ログの頭も同じ。modules/ecs）
#   $2：タスク定義（family か ARN）
run_once() {
  local name="$1" task_definition="$2" task stopped exit_code
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
    aws logs get-log-events --log-group-name "/ecs/$NAME/db-tasks" \
      --log-stream-name "$name/$name/${task##*/}" --query 'events[].message' --output text || true
    exit 1
  fi
  note "- $name：成功"
}

#!/usr/bin/env bash
# staging を、使うときだけ作る・使い終わったら消す（S1-19・ADR-022・ADR-027）
#
#   使い方：
#     infra/scripts/staging.sh up            作る → DB の準備（ユーザー・表・見本のデータ）→ /readyz の確認
#     infra/scripts/staging.sh down          お金のかかるもの（ECS・ALB・RDS・Valkey）と api-stg の DNS を消す
#     infra/scripts/staging.sh down --snapshot   消す前に、RDS のスナップショットを取る（復元の訓練のときだけ）
#
#   オプション：
#     --yes       terraform の「本当にやる？」を聞かない（安全網のジョブが使う）
#
#   要るもの：aws CLI（aws login 済み）・terraform・jq・curl・Cloudflare のトークン
#   （CLOUDFLARE_API_TOKEN。なければ macOS のキーチェーンから読む。api-stg の DNS を作る・消すのに要る）
#
# 消すのは、いつも infra/terraform/envs/staging（使うときだけの層）だけ。ずっと残す層（staging-persistent）の
# ディレクトリでは terraform を動かさない（S3 のバケット・ECR のイメージ・証明書を消さないため）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform/envs/staging"
NAME="${NAME:-yumeguri-staging}"
CLUSTER="$NAME"
KEYCHAIN_SERVICE="yumeguri-cloudflare-api-token"
READY_TIMEOUT_SECONDS=600

# shellcheck source=SCRIPTDIR/lib/ecs-one-off.sh
source "$SCRIPT_DIR/lib/ecs-one-off.sh"

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# 何分何秒かかったかを出す。$1：始めた時刻（秒）
elapsed() {
  local seconds=$(($(date +%s) - $1))
  printf '%d 分 %d 秒' $((seconds / 60)) $((seconds % 60))
}

check_aws() {
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS にログインしていない（または切れている）。先に aws login --profile yumeguri を実行し、"
    echo "export AWS_PROFILE=yumeguri をしてから、もう一度動かす"
    exit 1
  fi
}

# Cloudflare のトークン（api-stg の DNS を作る・消すのに要る）。値は画面に出さない
load_cloudflare_token() {
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    return
  fi
  if command -v security >/dev/null 2>&1; then
    CLOUDFLARE_API_TOKEN="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
  fi
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "Cloudflare のトークンが見つからない（CLOUDFLARE_API_TOKEN か、キーチェーンの $KEYCHAIN_SERVICE）"
    exit 1
  fi
  export CLOUDFLARE_API_TOKEN
}

# ---- up ----
up() {
  local started api_url deadline
  started="$(date +%s)"
  check_aws
  load_cloudflare_token

  echo "== 1. terraform apply（envs/staging）"
  terraform -chdir="$TF_DIR" init -input=false >/dev/null
  terraform -chdir="$TF_DIR" apply -input=false ${APPROVE[@]+"${APPROVE[@]}"}

  echo "== 2. DB の準備（ユーザー → 表 → 見本のデータ）"
  API_NETWORK="$(api_network)"
  if [ -z "$API_NETWORK" ]; then
    echo "API のサービスが見つからない（apply が途中で止まっていないか確かめる）"
    exit 1
  fi
  # タスク定義は family の名前で指定する（いちばん新しい版。apply で SSM のタグのイメージになっている）
  run_once db-bootstrap "$NAME-db-bootstrap"
  run_once db-migrate "$NAME-db-migrate"
  run_once db-seed "$NAME-db-seed"

  # サービスは apply のときに、DB のユーザーがまだない状態で起動している。DB に先につなぐタスク（ワーカーなど）は
  # 失敗していることがあるので、DB の準備のあとに起動し直して、落ち着くまで待つ
  echo "== 3. API・ワーカーを起動し直す"
  aws ecs update-service --cluster "$CLUSTER" --service api --force-new-deployment >/dev/null
  aws ecs update-service --cluster "$CLUSTER" --service worker --force-new-deployment >/dev/null
  aws ecs wait services-stable --cluster "$CLUSTER" --services api worker

  echo "== 4. /readyz が 200 になるまで待つ（最大 $((READY_TIMEOUT_SECONDS / 60)) 分）"
  api_url="$(terraform -chdir="$TF_DIR" output -raw api_url)"
  deadline=$(($(date +%s) + READY_TIMEOUT_SECONDS))
  until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$api_url/readyz")" = "200" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "::error::$api_url/readyz が 200 にならなかった"
      exit 1
    fi
    sleep 10
  done

  note "- up：完了（$(elapsed "$started")）。$api_url/readyz が 200"
  echo
  echo "使い終わったら：infra/scripts/staging.sh down"
  echo "消し忘れても、今夜 3:00（日本時間）に安全網が消す。明日以降も残すときは："
  echo "  gh variable set KEEP_UNTIL --repo tkt-devs/yumeguri --body YYYY-MM-DD"
}

# ---- down ----
down() {
  local started targets
  started="$(date +%s)"
  check_aws
  # api-stg の DNS は ALB の住所を指しているので、ALB を消すと terraform が一緒に消す（依存しているものも消す）
  load_cloudflare_token

  # お金のかかるものと、ALB を指している DNS。VPC・NAT の EC2 は残す（全部消すときは、envs/staging で terraform destroy）
  targets=(-target=module.ecs -target=module.alb -target=module.iam_ecs -target=module.rds -target=module.valkey
    -target=cloudflare_dns_record.api)

  if [ "$SNAPSHOT" = "true" ]; then
    take_snapshot
  fi

  echo "== terraform destroy（envs/staging のお金のかかるものだけ）"
  terraform -chdir="$TF_DIR" init -input=false >/dev/null
  terraform -chdir="$TF_DIR" destroy -input=false ${APPROVE[@]+"${APPROVE[@]}"} "${targets[@]}"

  note "- down：完了（$(elapsed "$started")）"
}

# 復元の訓練のときだけ。スナップショットは消すまで保存料がかかるので、使い終わったら消す
take_snapshot() {
  local id
  id="$NAME-manual-$(date +%Y%m%d-%H%M)"
  if ! aws rds describe-db-instances --db-instance-identifier "$NAME" >/dev/null 2>&1; then
    echo "RDS がないので、スナップショットは取らない"
    return
  fi
  echo "== RDS のスナップショットを取る：$id（数分かかる）"
  aws rds create-db-snapshot --db-instance-identifier "$NAME" --db-snapshot-identifier "$id" >/dev/null
  aws rds wait db-snapshot-available --db-snapshot-identifier "$id"
  echo "取った。使い終わったら消す：aws rds delete-db-snapshot --db-snapshot-identifier $id"
}

# ---- 引数 ----
COMMAND="${1:-}"
[ -n "$COMMAND" ] || usage
shift
# 空の配列を "${APPROVE[@]}" で使うと、macOS の bash 3.2 では set -u で止まるので、${APPROVE[@]+...} の形で使う
APPROVE=()
SNAPSHOT=false
for arg in "$@"; do
  case "$arg" in
    --yes) APPROVE=(-auto-approve) ;;
    --snapshot) SNAPSHOT=true ;;
    *) usage ;;
  esac
done

case "$COMMAND" in
  up) up ;;
  down) down ;;
  *) usage ;;
esac

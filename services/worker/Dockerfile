# syntax=docker/dockerfile:1
# ワーカーのイメージ。services/worker で作る
#   docker buildx build --platform linux/arm64 -t yumeguri-worker:local services/worker
# 同じイメージで、Celery のワーカー（初期）と、内部の API（python -m app.api）の両方を動かす

# ---- 1段目：uv で部品を入れる ----
FROM python:3.13-slim-trixie AS build
COPY --from=ghcr.io/astral-sh/uv:0.13.5 /uv /bin/uv
# 起動を速くするため .pyc を先に作る。部品はコピーで置く（2段目へ持っていくため）。Python は箱のものを使う
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
# 部品の一覧だけを先にコピーする。コードを変えただけなら、次の sync は前の結果（キャッシュ）を使う
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
COPY app ./app
# 自分のコードの .pyc も先に作る（実行のユーザーは /app に書けないので、起動のたびに作り直さないように）
RUN python -m compileall -q app

# ---- 2段目：部品（.venv）とコードだけを持っていく（uv・開発用の部品は入らない） ----
FROM python:3.13-slim-trixie AS runtime
# root ではないユーザーを作って、そのユーザーで動かす
RUN useradd --system --uid 10001 --no-create-home worker
WORKDIR /app
# 部品（変わることが少ない）とコード（よく変わる）を別の層にする
# コードだけを変えたときは、小さいコードの層だけを送り直せばよい
COPY --from=build /app/.venv /app/.venv
COPY --from=build /app/app /app/app
# .venv の中の celery・python を使う。ログを溜めずにすぐ出す
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER worker
# Linux では Celery の初期の prefork で動く（時間の上限が効く）
# HEALTHCHECK は書かない：Celery のワーカーには HTTP の窓口がなく、SQS では Celery の ping も使えない
# 内部の API のヘルスチェックは docker-compose.yml に、本番は ECS のタスク定義に書く（S1-15）
# 読むキュー（jobs-default・jobs-heavy）は app/celery_app.py の task_queues で決まる
CMD ["celery", "-A", "app.celery_app", "worker"]

# AGENTS.md — ワーカー（services/worker）

`services/worker` の中では、リポジトリ全体のルール（`/AGENTS.md`、特に「Python のコード」）に加えて、このルールを守る。

## 前提

| 項目 | 使うもの |
| --- | --- |
| 言語 | Python 3.13（`.python-version`。Celery が対応を明記している版） |
| 部品の管理 | uv（`pyproject.toml`・`uv.lock`）。`pip install` を使わない |
| ジョブ | Celery。ブローカーは Amazon SQS（ローカルは LocalStack） |
| 内部の API | FastAPI（`/internal/...`。外に公開しない） |
| 設定 | pydantic-settings（`app/config.py`） |
| ログ | JSON を標準出力へ（`app/logs.py`。項目名は API の pino と同じ） |
| 検査 | pytest・ruff・mypy（strict） |

## ディレクトリの構成

```
services/worker/
├── app/
│   ├── config.py       # 環境変数の検証。os.environ を読むのはここだけ
│   ├── logs.py         # JSON のログと、相関 ID
│   ├── celery_app.py   # Celery の設定（キュー・時間の上限・受け取り完了の時機）
│   ├── api.py          # FastAPI（内部の API）。python -m app.api で起動
│   └── tasks/          # タスク（ジョブの種類ごとに1ファイル）
└── tests/
```

## キューと SQS

- キューは `jobs-default`・`jobs-heavy` の2つだけ（ADR-012）。**Celery にキューを作らせない**（`predefined_queues`・`task_create_missing_queues=False`）。キューは Terraform（ローカルは `docker/localstack/init/01-resources.sh`）が作る
- **可視性タイムアウトは SQS のキューの側で決める**（`predefined_queues` のときは、Celery の `visibility_timeout` は効かない）
- ジョブの実行時間の上限（`soft_time_limit`・`time_limit`）は、そのキューの可視性タイムアウトより短くする（要件定義書 11.2）
- SQS の接続先・認証をコードに書かない。ローカルは `AWS_PROFILE=localstack`、staging・本番は ECS のタスクロール

## タスクの書き方

- タスクの名前は `@celery_app.task(name="領域.動き")` で明示する（API が名前で送るので、関数の場所を変えても名前が変わらないように）
- 引数は**名前つきの引数（kwargs）だけ**。JSON にできる値（ID・数・文字列）だけを渡す。大きなデータや個人情報を渡さない（DB・S3 から読む）
- **何回実行しても結果が同じ**になるように書く（SQS は「少なくとも1回」届く。`task_acks_late=True` なので、途中で落ちたジョブはもう一度実行される）
- ジョブの状態・結果は DB の `Job` の表に書く（S3-01）。Celery の結果の保存（Result Backend）は使わない
- ワーカーが読み書きできる表は `Job`・`Photo` だけ（ADR-005）。表の形を変えない（Prisma だけが管理する）

## API から送られるメッセージ

- API（`apps/api/src/adapters/celeryMessage.ts`）が、Celery のメッセージの形（protocol 2）を作って SQS に送る
- 相関 ID は、メッセージのヘッダーの `correlationId` で届く。`task_prerun` でログに付ける。ヘッダーの名前を変えるときは、API 側も同時に変える
- タスクの名前・引数を変えるときは、API 側の呼び出しも同時に変える

## ログ

- `logging.getLogger(__name__)` を使う。`print` を使わない
- 項目は `extra={...}` で渡す（キーは camelCase：`jobId` など。API のログとそろえる）
- 出さないもの：トークン・パスワード・シークレット・メールアドレス・IP アドレス。例外のメッセージに外部の SDK の接続情報が入ることがあるので、例外をそのままログに出す前に中身を考える

## ローカルでの起動

- `docs/runbook/local-setup.md` の「ワーカーを起動する」
- Mac では `.env` の `CELERY_POOL=solo` で起動する（`app/config.py`。本番の初期は `prefork`）。Mac の Python は子プロセスを spawn で作るため、Celery の初期の `prefork` は動かない（Celery の公式ドキュメントの Concurrency の章）。`solo` では時間の上限が効かないので、上限の動きは Linux のコンテナ（S1-10）で確かめる
- コードを変えても、ワーカーは自動で再起動しない。手で止めて起動し直す

## 提出前のチェック

```bash
uv run --frozen ruff check app tests
uv run --frozen ruff format --check app tests
uv run --frozen mypy
uv run --frozen pytest
```

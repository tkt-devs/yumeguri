# ローカルの開発環境（DB・Valkey・S3・SQS）

`docker-compose.yml` で、本番の AWS の代わりを Mac の中に起動する。

| サービス | 本番 | ローカル | Mac からの接続先 |
| --- | --- | --- | --- |
| `postgres` | RDS（PostgreSQL 18） | `postgres:18` | `127.0.0.1:5433` |
| `valkey` | ElastiCache（Valkey 9.1） | `valkey/valkey:9.1` | `127.0.0.1:6380` |
| `aws` | S3・SQS | LocalStack（Hobby） | `http://localhost:4566` |

ポートを 5433・6380 にずらしているのは、ほかのプロジェクトの PostgreSQL・Redis と同時に起動できるようにするため。

## 最初に一度だけ

1. Docker Desktop を入れて、起動しておく
2. LocalStack のアカウントを作り、[Auth Tokens](https://app.localstack.cloud/workspace/auth-tokens) で token をコピーする（Hobby は商用で使えない）
3. `.env` を作って、token と、マイグレーション用の DB の接続先（`MIGRATE_DATABASE_URL`）を入れる（`.env` は Git に入らない）

   ```bash
   cp .env.example .env
   ```

   ```
   MIGRATE_DATABASE_URL=postgresql://yumeguri_migrator:migrator_local@localhost:5433/yumeguri
   ```

4. LocalStack 専用の AWS のプロフィールを作る。ダミーの鍵と、送り先の `endpoint_url` を入れておくので、**本物の AWS には届かない**。本物の認証情報を LocalStack に使わない

   ```bash
   aws configure set aws_access_key_id test --profile localstack
   aws configure set aws_secret_access_key test --profile localstack
   aws configure set region ap-northeast-1 --profile localstack
   aws configure set endpoint_url http://localhost:4566 --profile localstack
   ```

## 起動・確認

```bash
docker compose up -d
docker compose ps    # 3つとも (healthy) になれば使える。LocalStack は数十秒かかる
```

```bash
docker compose exec postgres psql -U yumeguri_app -d yumeguri -c "select current_user;"
docker compose exec valkey valkey-cli ping
aws --profile localstack s3 ls
aws --profile localstack sqs list-queues
```

## API と画面を起動する

| アプリ | 環境変数のファイル | 起動 | 場所 |
| --- | --- | --- | --- |
| API（`apps/api`） | `apps/api/.env`（`cp apps/api/.env.example apps/api/.env` して `DATABASE_URL` を入れる。SQS の値は `.env.example` のままでよい） | `pnpm --filter @yumeguri/api dev` | `http://localhost:3001` |
| 画面（`apps/web`） | `apps/web/.env.local`（`cp apps/web/.env.example apps/web/.env.local`） | `pnpm --filter @yumeguri/web dev` | `http://localhost:3000` |

- 画面のトップに「API の状態：つながっています（API・DB）」が出れば、画面 → API → DB までつながっている（S1-08 の確認用の表示。あとで消す）
- 「つながりません」のとき：API が起動しているか、`apps/api/.env` の `WEB_ORIGIN` が `http://localhost:3000`（最後に `/` を付けない）か、`apps/web/.env.local` の `NEXT_PUBLIC_API_URL` が `http://localhost:3001` かを見る。ブラウザの開発者ツールのコンソールに CORS のエラーが出ていれば、`WEB_ORIGIN` が違う
- `apps/web/.env.local` の `NEXT_PUBLIC_` で始まる値はブラウザに送られるので、秘密の値を書かない

## ワーカーを起動する（Python・Celery）

初めてのときだけ、`services/worker` で部品を入れて、`.env` を作る（`uv` は Homebrew で入れる：`brew install uv`）。

```bash
cd services/worker
uv sync
cp .env.example .env
```

ワーカー（キューを見張る）と、内部の API（FastAPI）は、別々のターミナルで起動する。

```bash
cd services/worker
uv run --env-file .env celery -A app.celery_app worker
```

```bash
cd services/worker
uv run --env-file .env python -m app.api    # http://localhost:8000/internal/healthz
```

API 側から、確かめ用のタスク（2つの数を足すだけ）をキューに入れる（リポジトリのいちばん上で）。

```bash
pnpm --filter @yumeguri/api enqueue:debug-add 2 3
```

ワーカーのログに `Task debug.add[…] received` → `"msg": "debug.add", … "result": 5` → `succeeded` が出れば、API → SQS → ワーカーまでつながっている。API の `job enqueued` のログと、ワーカーのログの `correlationId` が同じになる。

- `.env` の `CELERY_POOL=solo`：Mac では Celery の初期の `prefork` が動かない（子プロセスの作り方が違う）ので、1つのプロセスで順に実行する。`solo` では時間の上限が効かない。本番の Linux のコンテナは `prefork`
- コードを変えても、ワーカーは自動で再起動しない。`Ctrl+C` で止めて、起動し直す
- `Ctrl+C` で止めたときに受け取っていたメッセージは、キューの可視性タイムアウト（`jobs-default` は120秒）が過ぎてから、もう一度届く

## 全部を箱（コンテナ）で起動する

本番（ECS）で動かすのと同じイメージで、API・ワーカーも Docker で動かす（`docker-compose.yml` の `full` のプロファイル）。イメージは ARM（`linux/arm64`）向け（ADR-002）。Apple シリコンの Mac では、そのままビルドすると ARM になる。

```bash
docker compose --profile full up -d --build
docker compose --profile full ps    # api・worker-api が (healthy) になれば使える
curl -s localhost:3001/readyz       # {"status":"ok"}
curl -s localhost:8000/internal/healthz
docker images | grep yumeguri       # イメージの大きさ
```

| サービス | イメージ | Mac からの接続先 |
| --- | --- | --- |
| `api` | `apps/api/Dockerfile`（API を1つのファイルにまとめて、Node だけの箱に入れる） | `http://localhost:3001` |
| `worker` | `services/worker/Dockerfile`（Celery。Linux なので `prefork`） | なし |
| `worker-api` | `worker` と同じイメージで `python -m app.api` | `http://localhost:8000` |

- `pnpm --filter @yumeguri/api dev` や、`uv run … celery …` と同じポートを使うので、同時には起動しない。箱の API・ワーカーだけを止めるときは `docker compose --profile full stop api worker worker-api`
- 箱の中からは、`localhost` ではなく、サービスの名前（`postgres:5432`・`aws:4566`）でつなぐ。接続先と、ダミーの鍵は `docker-compose.yml` に書いてある
- コードを変えたら、`--build` を付けて起動し直す（イメージを作り直す）
- 1つのイメージだけを作るとき：`docker buildx build --platform linux/arm64 -t yumeguri-api:local -f apps/api/Dockerfile .`・`docker buildx build --platform linux/arm64 -t yumeguri-worker:local services/worker`

## DB の表を作る・やり直す（Prisma）

表の形は `prisma/schema.prisma`、作った SQL は `prisma/migrations/`。Prisma のコマンドは、リポジトリのいちばん上で、マイグレーション用のユーザー（`.env` の `MIGRATE_DATABASE_URL`）として DB につなぐ。API はアプリ用のユーザー（`apps/api/.env` の `DATABASE_URL`）でつなぐ。

| コマンド | 何をするか | 使うとき |
| --- | --- | --- |
| `pnpm exec prisma migrate dev` | まだ実行していないマイグレーションを実行する。`schema.prisma` を変えていれば、差分の SQL を作ってから実行する（`--name <名前>` を付ける） | 最初の1回・表を変えたとき・`main` を取り込んだとき |
| `pnpm exec prisma migrate dev --create-only --name <名前>` | 空のマイグレーションを作るだけ（実行しない） | Prisma で書けない制約・権限を、SQL で手で書くとき |
| `pnpm exec prisma db seed` | 架空のデータ（団体3つ・システム管理者1人・銭湯10軒と営業時間）を入れる。何回実行しても同じ結果になる | 表を作ったあと |
| `pnpm exec prisma generate` | API が使う Prisma Client を `apps/api/src/generated/prisma` に作る（Git に入らない）。初めての `pnpm install` や、依存が変わった `pnpm install` のあとには自動で実行される（`Already up to date` のときは実行されない） | `schema.prisma` を変えたとき（Prisma 7 の `migrate dev` は作り直さないので、そのあとに必ず実行する）・`main` を取り込んだとき |
| `pnpm exec prisma migrate status` | どこまで実行したかを見る | 迷ったとき |

DB を空からやり直すときは、`docker compose down -v` → `docker compose up -d` → `pnpm exec prisma migrate dev` → `pnpm exec prisma db seed`。

- 一度 `main` に入れたマイグレーションのファイルは、書き換えない。直すときは、新しいマイグレーションを足す
- マイグレーションは、DB のユーザー（`yumeguri_app`・`yumeguri_worker`）の権限を変える。なので、**ユーザーがない DB では失敗する**。ローカルは `01-roles.sql` が先に作る。staging・本番の RDS では、同じ内容の SQL を最初に一度だけ実行してから、`prisma migrate deploy` を実行する
- Prisma の 8 は、まだ試験版（RC）なので上げない（`Update available … 8.0.0-rc` の表示は無視する）

## 止める・片付ける

| コマンド | 箱 | DB のデータ | 使うとき |
| --- | --- | --- | --- |
| `docker compose stop` | 残る | 残る | 毎日の終わり。`docker compose start` で再開 |
| `docker compose down` | 消す | 残る | 設定を変えて、箱を作り直したいとき |
| `docker compose down -v` | 消す | **消える** | `01-roles.sql` を直したとき・最初からやり直したいとき |

## 起動のときに自動で実行されるもの

- `docker/postgres/init/01-roles.sql`：DB のユーザーを3つ作る。**データが空のときだけ** 実行される。直したら `docker compose down -v` → `docker compose up -d`
  - `yumeguri_migrator`（パスワード `migrator_local`）：表の作成・変更（マイグレーション）
  - `yumeguri_app`（`app_local`）：データの読み書きだけ。表は作れない（NFR-SEC-03）
  - `yumeguri_worker`（`worker_local`）：`Job`・`Photo` だけ（ADR-005）
- `docker/localstack/init/01-resources.sh`：バケット2つ（`yumeguri-local-private`・`yumeguri-local-public`）と、キュー2つ（`jobs-default`・`jobs-heavy`）とそれぞれの DLQ を作る。LocalStack は止めると中身を忘れるので、**起動のたびに** 実行される。実行できる権限（`chmod +x`）が要る

## 困ったとき

- **`port is already allocated`**：そのポートを、ほかのものが使っている。`lsof -nP -iTCP:5433 -sTCP:LISTEN` で調べる
- **`LOCALSTACK_AUTH_TOKEN を .env に書いてください`**：`.env` がないか、token が空
- **バケットやキューがない**：`curl -s localhost:4566/_localstack/init/ready` で、スクリプトが `SUCCESSFUL` になっているか見る。`docker compose logs aws` でエラーを探す
- **`Unable to locate credentials`**：`aws` に `--profile localstack` を付け忘れている
- **`The datasource.url property is required`**：いちばん上の `.env` に `MIGRATE_DATABASE_URL` がない
- **API の型チェックで `Cannot find module '../generated/prisma/client'`**：Prisma Client がまだない。`pnpm exec prisma generate`
- **`/readyz` が 503 で、ログに `"failed":["db"]`**：DB が止まっているか、`apps/api/.env` の `DATABASE_URL` が違う。`docker compose ps` で `postgres` を見る
- **ワーカーで `ValueError: not enough values to unpack (expected 3, got 0)`**：`services/worker/.env` に `CELERY_POOL=solo` がない（Mac）
- **ワーカーで `UndefinedQueueException`**：`-Q` に `jobs-default`・`jobs-heavy` 以外のキューを書いている
- **ワーカーがメッセージを受け取らない**：`services/worker/.env` の `AWS_PROFILE=localstack` と、キューの URL を見る。`aws --profile localstack sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/jobs-default --attribute-names All` で、メッセージがたまっているか見る
- **`docker compose --profile full up` で `port is already allocated`（3001・8000）**：`pnpm dev` の API や、`uv run` の内部の API が起動している。止めてから起動する
- **箱の API の `/readyz` が 503**：DB の表がまだない（`pnpm exec prisma migrate dev`）か、`postgres` が起動していない
- **LocalStack のバージョンを上げるとき**：`01-resources.sh` で使っている `awslocal` は非推奨になっている（2026.10.4 では動く）。上げたあとに動かなければ、`lstk aws` などに書き換える

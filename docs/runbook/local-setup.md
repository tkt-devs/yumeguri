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
3. `.env` を作って、token を入れる（`.env` は Git に入らない）

   ```bash
   cp .env.example .env
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
- **LocalStack のバージョンを上げるとき**：`01-resources.sh` で使っている `awslocal` は非推奨になっている（2026.10.4 では動く）。上げたあとに動かなければ、`lstk aws` などに書き換える

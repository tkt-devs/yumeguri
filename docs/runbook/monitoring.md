# 監視（Sentry・アラーム）

v0.1 の監視は、Sentry（エラー）と CloudWatch（ログ・アラーム）にする（ADR-017・S1-20）。

## Sentry

組織 `shota-moriyama`（無料の Developer プラン・データはアメリカ）に、プロジェクトを3つ作ってある。

| プロジェクト | 送るもの | DSN の置き場所 |
| --- | --- | --- |
| `yumeguri-api` | API（Hono）の予期しないエラー（`errors/problem.ts` で 500 にしたもの） | Secrets Manager `yumeguri/staging/sentry-dsn` の `api` |
| `yumeguri-worker` | ワーカー（Celery）のタスクのエラー | 同じシークレットの `worker` |
| `yumeguri-web` | 画面（Next.js）のブラウザとサーバーのエラー | Vercel の環境変数 `NEXT_PUBLIC_SENTRY_DSN` |

- **環境**（environment）：staging・production。API は `NODE_ENV`、ワーカーは `SENTRY_ENVIRONMENT`、画面は Vercel の `NEXT_PUBLIC_SENTRY_ENVIRONMENT`
- **リリース**（release）：Git のコミット ID の先頭 12 文字。API・ワーカーはイメージを作るときに入れる（CD の `--build-arg SENTRY_RELEASE`）。画面は Vercel の `VERCEL_GIT_COMMIT_SHA` から作る（`next.config.ts`）
- **送らないもの**（ADR-017）：例外のメッセージ（秘密の値が入りうる）・パンくず・Cookie・ヘッダー・本文・スタックの変数の値・タスクの引数。送るのは、エラーの種類とスタック（どこで起きたか）と相関 ID（API だけ）
- 相関 ID（タグ `correlation_id`）で、CloudWatch Logs の同じリクエストを探せる（`docs/architecture.md`）
- ローカルでは DSN を空にしておく（Sentry に送らない）

## アラーム

| アラーム | 鳴る条件 | 置き場所 |
| --- | --- | --- |
| `yumeguri-staging-alb-5xx-rate` | 5 分間で、5xx（API と ALB の両方）が全部のリクエストの 5 % を超えた | `envs/staging`（`modules/alarms`） |
| `yumeguri-staging-api-no-running-tasks` | API のタスクが 2 分続けて 0 | 同上 |
| `yumeguri-staging-worker-no-running-tasks` | ワーカーのタスクが 2 分続けて 0 | 同上 |

- 鳴ったとき・戻ったときに、SNS のトピック `yumeguri-staging-alarms`（`envs/staging-persistent`）からメールが届く。宛先は `terraform.tfvars` の `alarm_email`（リポジトリには書かない）
- メールを登録すると、確認のメールが届く。「Confirm subscription」を押すまで、知らせは届かない
- アラームは staging と一緒に作って消す（`staging.sh down`）。残すと、データがなくて鳴り続けるため
- タスクの数は、Container Insights を使わず（費用がかかる）、タスクが動いている間だけ届く CPU のメトリクスの数で見る。`up` の直後は、タスクが起動するまで「鳴った」になることがある

試しに鳴らす（メールが届くかの確認）：

```bash
aws cloudwatch set-alarm-state --alarm-name yumeguri-staging-api-no-running-tasks \
  --state-value ALARM --state-reason "試しに鳴らした"
```

次の評価（1〜数分）で、本当の状態に戻る（戻ったときもメールが届く）。

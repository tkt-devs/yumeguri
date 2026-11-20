# staging を作る・消す（up / down）

staging は、使うときだけ作る（ADR-022・ADR-027）。動かしている間は、1日 約 3 ドルかかる。**使い終わったら、その日のうちに消す。**

## 準備（毎回）

```bash
aws login --profile yumeguri
export AWS_PROFILE=yumeguri
```

Cloudflare のトークンは、スクリプトが macOS のキーチェーン（`yumeguri-cloudflare-api-token`）から読む。値は画面に出ない。

## 作る（up）

```bash
infra/scripts/staging.sh up
```

1. `terraform apply`（`envs/staging`）。作るものの一覧が出るので、`destroy` が 0 か確かめてから `yes` を打つ
2. DB の準備：ユーザーの作成（`db-bootstrap`）→ 表（`db-migrate`）→ 見本のデータ（`db-seed`）。どれも ECS の単発のタスク
3. API・ワーカーを起動し直す（DB の準備の前に起動して失敗したタスクを、やり直させる）
4. `https://api-stg.sento-stamprally.com/readyz` が 200 になるまで待つ（最大 10 分）
5. かかった時間を出す

動かすイメージは、いちばん新しくデプロイしたもの（SSM のパラメータ `/yumeguri/staging/image-tag`）。データは毎回、空から見本のデータで作られる。

## 消す（down）

```bash
infra/scripts/staging.sh down
```

`envs/staging` の、お金のかかるもの（ECS・ALB・RDS・Valkey・タスクのロール）と、`api-stg` の DNS を消す。VPC・NAT の EC2・ずっと残す層（ECR・S3・証明書）は残る。

復元の訓練をするときだけ、消す前に RDS のスナップショットを取る。スナップショットは保存料がかかるので、使い終わったら消す。

```bash
infra/scripts/staging.sh down --snapshot
```

## 消し忘れの安全網

毎晩 3:00（日本時間）に、GitHub Actions（「staging の消し忘れの安全網」）が `staging.sh down --yes` を動かす。止まっていれば、何もしない。

明日以降も残しておきたいときは、リポジトリの変数 `KEEP_UNTIL` に日付（日本時間）を入れる。その日が終わるまでは消さない。

```bash
gh variable set KEEP_UNTIL --repo tkt-devs/yumeguri --body 2026-11-25   # 11/25 の夜までは残す
gh variable delete KEEP_UNTIL --repo tkt-devs/yumeguri                  # やめる
```

すぐに安全網を動かして確かめるとき：

```bash
gh workflow run staging-reaper.yml --repo tkt-devs/yumeguri --ref main
```

## 最初の1回だけ：安全網の準備

1. `envs/staging-persistent` を apply する（消す専用のロール `yumeguri-staging-github-reaper` ができる）
2. GitHub に Environment `staging-reaper` を作り、**`main` からだけ使えるようにする**（Deployment branches）。これがないと、ほかのブランチのワークフローからも、消す専用のロールを引き受けられてしまう（ロールの条件は Environment の名前だけを見るため）
3. ロールの ARN を、Environment のシークレット `AWS_REAPER_ROLE_ARN` に入れる

   ```bash
   cd infra/terraform/envs/staging-persistent
   terraform output -raw github_reaper_role_arn | gh secret set AWS_REAPER_ROLE_ARN --repo tkt-devs/yumeguri --env staging-reaper
   ```

4. Cloudflare で、**DNS だけを書けるトークン**を作る（権限：Zone の Zone Read・DNS Edit。対象：`sento-stamprally.com` だけ）。Environment のシークレット `CLOUDFLARE_API_TOKEN` に入れる（値はコマンドに書かず、聞かれたら貼る）

   ```bash
   gh secret set CLOUDFLARE_API_TOKEN --repo tkt-devs/yumeguri --env staging-reaper
   ```

## かかった時間（作業ログ）

| 日付 | up | down |
| --- | --- | --- |
| 2026-11-20（手元の `up` / `down`） | 16 分 43 秒（作り始めから。IAM のロールを待つやり直し 1 回） | 4 分 52 秒 |
| 2026-11-20（安全網を手で動かした） | — | 5 分 2 秒 |

## 詰まりやすい点

- 公開のリポジトリでは、60日間なにも push がないと、GitHub が定期実行を止める（安全網も止まる）。長く空けたあとは、Actions の画面で「staging の消し忘れの安全網」が有効か確かめる
- GitHub の定期実行は、混んでいると数十分〜数時間遅れることがある（GitHub の仕様）。3:00 ちょうどに消えるとは限らない
- `aws login` は1日で切れる。スクリプトが「ログインしていない」と止まったら、ログインし直す
- `up` の途中で止まったとき（DB の準備の失敗など）は、`up` をもう一度動かしてよい。どの手順も、何回動かしても同じ結果になる
- 消したあとの翌日に、Cost Explorer で、RDS・ELB・ECS・ElastiCache の費用が 0 になっているかを確かめる

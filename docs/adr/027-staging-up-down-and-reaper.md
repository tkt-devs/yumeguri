# ADR-027: staging は1つのコマンドで作って消し、消し忘れは毎晩 GitHub Actions が消す

- 状態：決定
- 日付：2026-11-19

## 背景

staging は使うときだけ作る（ADR-022）。S1-18 までは、作る・消すのに次の手順を手で打っていた。

- 作る：`terraform apply` → CD を手で動かす（DB のユーザー・マイグレーション）→ `/readyz` を `curl` で確かめる
- 消す：`terraform destroy -target=…` を6つ並べて打つ

S1-18 の途中で作業が止まり、**staging を約5日間つけっぱなしにして、約 15 ドル余分にかかった**。手順を短くすることと、消し忘れても止まる仕組みが要る。

## 選択肢

**作る・消すのまとめ方**

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| シェルのスクリプト（`infra/scripts/staging.sh up / down`） | 手元でも GitHub Actions でも同じものを使える。単発のタスクの処理を CD と共有できる | bash の書き方の注意が要る（macOS は bash 3.2） |
| Makefile | よく使われる形 | 待つ・くり返す・失敗したらログを出す、を書くのに向かない |

**消し忘れの安全網**

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| GitHub Actions の定期実行で、`staging.sh down` を動かす | 手元と同じ消し方。state も正しく更新される | GitHub に、消す権限のロールと Cloudflare のトークンが要る |
| AWS の中（EventBridge と Lambda）で、CLI で消す | GitHub に権限を置かない | terraform の state とずれる。次の up が壊れる |
| AWS Budgets のアラートで知らせるだけ | 作るのが簡単 | 知らせるだけで、止まらない。夜中に気づけない |

**消す権限の置き方**

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| 消す専用のロールを作り、GitHub の Environment（`staging-reaper`）のジョブからだけ引き受けられるようにする | CD や PR のジョブからは使えない。消せるものを名前の頭で絞れる | ロールが1つ増える |
| CD のデプロイ用のロールに、消す権限を足す | ロールが増えない | `main` のどのワークフローからでも消せてしまう。ADR-026 で「CD は Terraform を動かさない」と決めたことに反する |

## 決めたこと

- `infra/scripts/staging.sh up` で、`terraform apply` → DB のユーザーの作成（`db-bootstrap`）→ マイグレーション（`db-migrate`）→ 見本のデータ（`db-seed`）→ `/readyz` が 200 になるまで待つ、を行う。かかった時間を出す
- `infra/scripts/staging.sh down` で、`envs/staging` のお金のかかるもの（ECS・ALB・RDS・Valkey・タスクのロール）と、ALB を指している `api-stg` の DNS を消す。VPC・NAT の EC2 は残す。`--snapshot` を付けたときだけ、消す前に RDS のスナップショットを取る
- スクリプトは `envs/staging` でしか terraform を動かさない（ずっと残す層を消さない）
- 単発のタスクを動かして待つ処理は、`infra/scripts/lib/ecs-one-off.sh` にまとめ、CD（`deploy-staging.sh`）と共有する
- **毎晩 3:00（日本時間）に、GitHub Actions（`.github/workflows/staging-reaper.yml`）が `staging.sh down --yes` を動かす**。止まっていれば、何も消さずに終わる
- リポジトリの変数 `KEEP_UNTIL`（`YYYY-MM-DD`、日本時間）があれば、その日が終わるまでは消さない。書き方がおかしいときは、無視して消す
- 消す専用のロール（`modules/github_reaper`）は、Environment `staging-reaper` のジョブの身分証（sub）からだけ引き受けられる。読む権限は `ReadOnlyAccess`、消す権限は `yumeguri-staging` で始まる、使うときだけの層のリソースだけ。作る権限はない
- Cloudflare のトークンは、**DNS だけを書ける専用のもの**を作り、Environment のシークレットに置く（手元のトークンは WAF・ゾーンの設定も変えられるので、GitHub には置かない）

## 理由

- terraform で消さないと、state と AWS がずれて、次の `up` が失敗する。安全網も terraform で消す
- `-target` で ALB を消すと、ALB を指している DNS のレコードも terraform が一緒に消す（依存しているものも消すため）。そのため、安全網にも Cloudflare のトークンが要る。トークンの権限を DNS だけに絞って、漏れたときの被害を小さくする
- 費用が止まらないことの方が、残しておきたい staging が消えることより困る。staging はいつでも `up` で作り直せる（データは毎回シードで作る）

## 捨てた選択肢

- **EventBridge と Lambda で消す**：state とずれるので採らない
- **知らせるだけ**：止まらないので採らない（S1-20 で、費用のアラームは別に作る）
- **CD のロールに消す権限を足す**：権限が広がりすぎるので採らない

## リスクと、その対策

- `KEEP_UNTIL` を設定し忘れると、使っている途中の夜中に消える → `up` の最後に、残すときのコマンドを出す。消えても `up` で作り直せる
- 安全網のロールは `ReadOnlyAccess` を持つので、このアカウントのほとんどのものを読める → Environment のジョブからだけ引き受けられるようにし、シークレットの中身は、terraform が読むものだけに絞る
- 安全網が失敗したとき（権限の不足など）、気づけない → GitHub Actions の失敗のメールで気づく。S1-20 で費用のアラームも作る

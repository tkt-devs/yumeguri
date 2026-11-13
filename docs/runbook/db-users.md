# RDS に DB のユーザーを作る

staging・production の RDS に、アプリが使う DB のユーザー（`yumeguri_migrator`・`yumeguri_app`・`yumeguri_worker`）を作る手順。ローカルの `docker/postgres/init/01-roles.sql`（ユーザー）・`02-grants.sql`（権限）と同じことを、RDS に行う。

## どこに何があるか

| もの | 場所 | 作るところ |
| --- | --- | --- |
| 管理者（`yumeguri_admin`）のパスワード | Secrets Manager（RDS が作る。名前は `rds!db-…`） | RDS（`manage_master_user_password`） |
| 3人のユーザーのパスワード | Secrets Manager の `yumeguri/staging/db/<ユーザー名>`（`{"username": …, "password": …}`） | Terraform（`modules/rds`。state には残らない） |
| ユーザーそのもの | RDS の中 | **この手順**（SQL） |

## 実行の方法（S1-17）

踏み台の EC2 は使わない。**ECS の単発のタスク `yumeguri-staging-db-bootstrap`** で実行する。**CD（`infra/scripts/deploy-staging.sh`）が、デプロイのたびにマイグレーションの前に動かす**ので、ふだんは手で動かさない。

- スクリプト：`apps/api/scripts/db-bootstrap.ts`（イメージ `yumeguri-db-tasks`。`apps/api/Dockerfile` の `db-tasks`）
- 管理者として RDS の `yumeguri` に TLS でつなぎ、RDS の CA の束で証明書を確かめる
- **何回動かしても同じ結果になる**：ユーザーがなければ作り、あればパスワードを今のシークレットの値に合わせる。GRANT・拡張機能は、もう付いていても変わらない
- パスワードは、タスク定義の `secrets` で環境変数として渡す。ログには出さない
- 管理者のパスワードを読めるのは、DB の準備用のタスク実行ロール（`yumeguri-staging-db-tasks-execution`）だけ
- 門番は `api` のもの（`rds` の門番が、`api` からの 5432 を通す）

手で動かすときは、`gh workflow run cd.yml --ref main`（`infra/terraform/README.md`）。

## SQL

- ユーザーの作成：スクリプトの中（パスワードはシークレットの値。ユーザーがあれば、パスワードを合わせ直す）
- 権限：**`docker/postgres/init/02-grants.sql` をそのまま流す**（ローカル・CI と同じファイル。SQL をここに書き写さない）

ローカルとの違い：

- `yumeguri_migrator` に `CREATEDB` を付けない。Prisma の shadow DB は、ローカルの `migrate dev` だけで使い、RDS では `migrate deploy` しか使わないため
- `02-grants.sql` の `GRANT yumeguri_migrator TO CURRENT_USER` は、RDS のためのもの。RDS の管理者は本当の superuser ではなく、migrator の一員でないと `ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator` を作れない

`yumeguri_worker` の表ごとの権限（`Job`・`Photo` だけ。ADR-005）は、表を作るマイグレーションの中で付ける（ローカルと同じ）。

## TLS の証明書（RDS の CA）

RDS の証明書は、AWS 独自の認証局（RDS の CA）が発行している。OS が初めから信頼している一覧には入っていないので、そのままだと `certificate verify failed` になる（2026-11-06 に、試しの EC2 から確かめた）。

- 東京の CA の束を `docker/rds/ap-northeast-1-bundle.pem` に置き、API と `db-tasks` のイメージの `/certs/rds-ca.pem` に入れる（取ってきた場所：`https://truststore.pki.rds.amazonaws.com/ap-northeast-1/ap-northeast-1-bundle.pem`）
- API（`pg`）：`DATABASE_URL` の `sslmode=verify-full` ＋ `NODE_EXTRA_CA_CERTS=/certs/rds-ca.pem`
- `db-bootstrap`（`pg`）：`ssl: { rejectUnauthorized: true }` ＋ 同じ `NODE_EXTRA_CA_CERTS`
- **マイグレーション（Prisma の CLI）は `sslmode=verify-full` を知らない**。知らない値は `prefer`（証明書を確かめない）として扱われ、**偽の証明書でもつながってしまう**（2026-11-11 に、手元の試験で確かめた）。シークレットに、Prisma の書き方の URL（`prisma_url`：`sslmode=require&sslcert=/certs/rds-ca-prisma.pem&sslaccept=strict`）も入れておき、マイグレーションはそれを使う（`modules/rds`）
- **Prisma の CLI は、`sslcert` のファイルの最初の1枚しか読まない**。束（3枚）を渡すと、RDS が使う CA（RSA2048、束の3枚目）が読まれず、`certificate verify failed` になる（2026-11-12 に、本物の staging と、本物のイメージの中の試験で確かめた）。そのため、RDS が使う CA の1枚だけを `docker/rds/rds-ca-rsa2048-g1.pem` に置き、`db-tasks` のイメージの `/certs/rds-ca-prisma.pem` に入れる。RDS の CA は `modules/rds` の `ca_cert_identifier` で固定する（変えるときは、このファイルも変える）

## 注意

- RDS を作り直す（`down` → `up`）と、ユーザーも消える。**`up` のあとは CD を手で動かす**と、この手順とマイグレーションが流れる（S1-19 で `up` に組み込む）
- 3人のパスワードも、`up` のたびに新しく作られる（Terraform がシークレットを作り直すため）。手で控えておく必要はない

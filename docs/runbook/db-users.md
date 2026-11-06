# RDS に DB のユーザーを作る

staging・production の RDS に、アプリが使う DB のユーザー（`yumeguri_migrator`・`yumeguri_app`・`yumeguri_worker`）を作る手順。ローカルの `docker/postgres/init/01-roles.sql` と同じ内容を、**RDS を作るたびに1回だけ** 実行する。

## どこに何があるか

| もの | 場所 | 作るところ |
| --- | --- | --- |
| 管理者（`yumeguri_admin`）のパスワード | Secrets Manager（RDS が作る。名前は `rds!db-…`） | RDS（`manage_master_user_password`） |
| 3人のユーザーのパスワード | Secrets Manager の `yumeguri/staging/db/<ユーザー名>`（`{"username": …, "password": …}`） | Terraform（`modules/rds`。state には残らない） |
| ユーザーそのもの | RDS の中 | **この手順**（SQL） |

## 実行の方法（S1-15 で作る）

踏み台の EC2 は使わない。**ECS の単発のタスク**（マイグレーションと同じ仕組み）から、次の順で実行する。

1. タスクは、門番 `api` を付けて、非公開のサブネットで起動する（`rds` の門番が、`api` からの 5432 を通す）
2. タスク定義の `secrets` で、管理者のパスワードと、3人のパスワードを、環境変数として渡す
3. `psql`（`sslmode=require`）で、管理者として RDS の `yumeguri` に接続し、下の SQL を実行する
4. タスクのログに、パスワードを出さない（`psql` の `-v` で渡し、`echo` しない）

## SQL

ローカルとの違いは、次の2つ。

- `yumeguri_migrator` に `CREATEDB` を付けない。Prisma の shadow DB は、ローカルの `migrate dev` だけで使い、RDS では `migrate deploy` しか使わないため
- パスワードは、Secrets Manager の値を変数で渡す

```sql
-- psql -v migrator_pw=… -v app_pw=… -v worker_pw=… で渡す
CREATE ROLE yumeguri_migrator LOGIN PASSWORD :'migrator_pw';
CREATE ROLE yumeguri_app      LOGIN PASSWORD :'app_pw';
CREATE ROLE yumeguri_worker   LOGIN PASSWORD :'worker_pw';

GRANT CONNECT ON DATABASE yumeguri TO yumeguri_migrator, yumeguri_app, yumeguri_worker;
GRANT USAGE, CREATE ON SCHEMA public TO yumeguri_migrator;
GRANT USAGE ON SCHEMA public TO yumeguri_app, yumeguri_worker;

ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO yumeguri_app;
ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO yumeguri_app;

-- 拡張機能は、管理者しか作れない（RDS では rds_superuser の権限が要る）
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

`yumeguri_worker` の表ごとの権限（`Job`・`Photo` だけ。ADR-005）は、表を作るマイグレーションの中で付ける（ローカルと同じ）。

## TLS の証明書（RDS の CA）

RDS の証明書は、AWS 独自の認証局（RDS の CA）が発行している。OS が初めから信頼している一覧には入っていないので、そのままだと `certificate verify failed` になる（2026-11-06 に、試しの EC2 から確かめた）。

- AWS の公式の CA の束（東京）：`https://truststore.pki.rds.amazonaws.com/ap-northeast-1/ap-northeast-1-bundle.pem`
- コンテナのイメージに入れておき、`psql` は `sslmode=verify-full sslrootcert=<束のパス>`、アプリ（Prisma・Python）も同じ束を使う（S1-15）

## 注意

- RDS を作り直す（`down` → `up`）と、ユーザーも消える。**`up` のたびに、マイグレーションの前にこの手順を実行する**（S1-19 の `up` に入れる）
- 3人のパスワードも、`up` のたびに新しく作られる（Terraform がシークレットを作り直すため）。手で控えておく必要はない

-- DB のユーザーの権限（ローカル・CI・staging・本番で同じ。何回流しても同じ結果になる）
-- ローカル：docker の初期化で、01-roles.sql のあとに流れる
-- RDS：apps/api/scripts/db-bootstrap.ts が、ユーザーを作ったあとに流す（docs/runbook/db-users.md）

GRANT CONNECT ON DATABASE yumeguri TO yumeguri_migrator, yumeguri_app, yumeguri_worker;
GRANT USAGE, CREATE ON SCHEMA public TO yumeguri_migrator;
GRANT USAGE ON SCHEMA public TO yumeguri_app, yumeguri_worker;

-- 「migrator が今後作る表に、app が読み書きできる権限を自動で付ける」設定は、migrator の一員でないと作れない
-- RDS の管理者は本当の superuser ではないので、自分を migrator の一員にしてから設定する（ローカルでは何も変わらない）
GRANT yumeguri_migrator TO CURRENT_USER;
ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO yumeguri_app;
ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO yumeguri_app;

-- 拡張機能は、管理者しか作れない（RDS では rds_superuser の権限が要る）
CREATE EXTENSION IF NOT EXISTS pg_trgm;

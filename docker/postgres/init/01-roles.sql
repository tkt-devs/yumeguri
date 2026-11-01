-- マイグレーション用（表の作成・変更ができる。CREATEDB は Prisma の shadow DB のため。ローカルだけ）
CREATE ROLE yumeguri_migrator LOGIN CREATEDB PASSWORD 'migrator_local';
-- アプリ用（データの読み書きだけ）
CREATE ROLE yumeguri_app LOGIN PASSWORD 'app_local';
-- ワーカー用（Job と Photo だけ。ADR-005。権限は、表を作るマイグレーションのあとで付ける）
CREATE ROLE yumeguri_worker LOGIN PASSWORD 'worker_local';

GRANT CONNECT ON DATABASE yumeguri TO yumeguri_migrator, yumeguri_app, yumeguri_worker;
GRANT USAGE, CREATE ON SCHEMA public TO yumeguri_migrator;
GRANT USAGE ON SCHEMA public TO yumeguri_app, yumeguri_worker;

-- マイグレーション用のユーザーが今後作る表に、アプリ用のユーザーが読み書きできる権限を自動で付ける
ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO yumeguri_app;
ALTER DEFAULT PRIVILEGES FOR ROLE yumeguri_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO yumeguri_app;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- DB のユーザーを作る（ローカル・CI だけ。パスワードはローカル用の決まった値）
-- 権限は 02-grants.sql（staging・本番の RDS でも、同じファイルを db-bootstrap が流す）
-- マイグレーション用（表の作成・変更ができる。CREATEDB は Prisma の shadow DB のため。ローカルだけ）
CREATE ROLE yumeguri_migrator LOGIN CREATEDB PASSWORD 'migrator_local';
-- アプリ用（データの読み書きだけ）
CREATE ROLE yumeguri_app LOGIN PASSWORD 'app_local';
-- ワーカー用（Job と Photo だけ。ADR-005。権限は、表を作るマイグレーションのあとで付ける）
CREATE ROLE yumeguri_worker LOGIN PASSWORD 'worker_local';

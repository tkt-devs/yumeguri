// RDS に、アプリが使う DB のユーザー（migrator・app・worker）を作る（docs/runbook/db-users.md・S1-17）
// ECS の単発のタスク（db-bootstrap）で、管理者としてつないで実行する。何回実行しても同じ結果になる
//   - ユーザーがなければ作り、あればパスワードを今のシークレットの値に合わせる
//   - 権限は docker/postgres/init/02-grants.sql（ローカルと同じファイル）を流す
// パスワードはログに出さない（SQL の文をログに出さない）
// 使い方（db-tasks のイメージの中、/repo で）：node_modules/.bin/tsx apps/api/scripts/db-bootstrap.ts
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { loadDbBootstrapEnv } from '../src/config/env';
import { createLogger } from '../src/logger';

const GRANTS_SQL = new URL('../../../docker/postgres/init/02-grants.sql', import.meta.url);

const env = loadDbBootstrapEnv();
const logger = createLogger(env.LOG_LEVEL);

const users = [
  { name: 'yumeguri_migrator', password: env.MIGRATOR_PASSWORD },
  { name: 'yumeguri_app', password: env.APP_PASSWORD },
  { name: 'yumeguri_worker', password: env.WORKER_PASSWORD },
];

const client = new pg.Client({
  host: env.DB_HOST,
  port: env.DB_PORT,
  database: env.DB_NAME,
  user: env.DB_ADMIN_USERNAME,
  password: env.DB_ADMIN_PASSWORD,
  // 暗号化し、RDS の証明書を確かめる（名前の一致も確かめる）。RDS の CA の束は、イメージの
  // NODE_EXTRA_CA_CERTS で「信頼してよい発行元」に足してある（apps/api/Dockerfile）
  ssl: { rejectUnauthorized: true },
});

await client.connect();
try {
  for (const user of users) {
    const role = client.escapeIdentifier(user.name);
    const password = client.escapeLiteral(user.password);
    const { rowCount } = await client.query('SELECT 1 FROM pg_roles WHERE rolname = $1', [
      user.name,
    ]);
    // CREATE ROLE・ALTER ROLE のパスワードは、$1 の形で渡せない。escapeLiteral で文字列にする
    if (rowCount === 0) {
      await client.query(`CREATE ROLE ${role} LOGIN PASSWORD ${password}`);
      logger.info({ role: user.name }, 'role created');
    } else {
      await client.query(`ALTER ROLE ${role} LOGIN PASSWORD ${password}`);
      logger.info({ role: user.name }, 'role password updated');
    }
  }

  await client.query(readFileSync(GRANTS_SQL, 'utf8'));
  logger.info('db bootstrap done');
} finally {
  await client.end();
}

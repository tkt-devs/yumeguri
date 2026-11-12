import { parseEnv } from '@yumeguri/shared';
import { z } from 'zod';

// API が読む環境変数。process.env を読むのは、このファイルだけ
export const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']),
  PORT: z.coerce.number().int().positive().default(3001),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  // アプリ用の DB ユーザー（yumeguri_app）でつなぐ。表を作ったり消したりはできない
  DATABASE_URL: z.url(),
  // ブラウザから API を呼んでよい画面の場所（CORS）。最後に / を付けない（例：http://localhost:3000）
  WEB_ORIGIN: z.url().refine((value) => new URL(value).origin === value, {
    message: 'http(s)://ホスト名（:ポート）の形にする（パスや最後の / を付けない）',
  }),
  // ジョブのキューの URL（Terraform・ローカルは LocalStack の init のスクリプトが作る）
  // SQS の接続先と認証は、AWS の SDK が自分で決める（ローカルは AWS_PROFILE=localstack、本番は ECS のタスクロール）
  SQS_QUEUE_URL_DEFAULT: z.url(),
  SQS_QUEUE_URL_HEAVY: z.url(),
});
export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(source: Record<string, string | undefined> = process.env): Env {
  return parseEnv(EnvSchema, source);
}

// DB の準備用の単発のタスク（db-bootstrap。scripts/db-bootstrap.ts）が読む環境変数（S1-17）
// ECS のタスク定義が、Secrets Manager の値を渡す。API のサービスでは使わない
export const DbBootstrapEnvSchema = z.object({
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  DB_HOST: z.string().min(1),
  DB_PORT: z.coerce.number().int().positive().default(5432),
  DB_NAME: z.string().min(1).default('yumeguri'),
  // RDS の管理者（RDS が作ったシークレット）
  DB_ADMIN_USERNAME: z.string().min(1),
  DB_ADMIN_PASSWORD: z.string().min(1),
  // アプリが使う3人のユーザーのパスワード（Terraform が作ったシークレット）
  MIGRATOR_PASSWORD: z.string().min(1),
  APP_PASSWORD: z.string().min(1),
  WORKER_PASSWORD: z.string().min(1),
});
export type DbBootstrapEnv = z.infer<typeof DbBootstrapEnvSchema>;

export function loadDbBootstrapEnv(
  source: Record<string, string | undefined> = process.env,
): DbBootstrapEnv {
  return parseEnv(DbBootstrapEnvSchema, source);
}

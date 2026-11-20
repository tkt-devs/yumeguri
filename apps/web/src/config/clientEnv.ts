import { parseEnv } from '@yumeguri/shared';
import { z } from 'zod';

// ブラウザに出してよい環境変数（NEXT_PUBLIC_ で始まるもの）。値は、ビルドのときにコードへ埋め込まれる
// 秘密の値はここに書かない。サーバーだけで使う値は、使い始めるときに serverEnv.ts（'server-only'）を作る
const ClientEnvSchema = z.object({
  NEXT_PUBLIC_API_URL: z.url(),
  // エラーの送り先（Sentry の DSN。ADR-017・S1-20）。ブラウザに出る前提の値（Sentry もそう決めている）
  // なければ Sentry に送らない（ローカル・テスト）。空の文字列も「なし」とみなす
  NEXT_PUBLIC_SENTRY_DSN: z.preprocess(
    (value) => (value === '' ? undefined : value),
    z.url().optional(),
  ),
  // staging・production（Vercel の環境変数で決める）
  NEXT_PUBLIC_SENTRY_ENVIRONMENT: z.string().min(1).default('development'),
  // どのコードのエラーか（Git のコミット ID の先頭 12 文字。next.config.ts が Vercel の値から作る）
  NEXT_PUBLIC_SENTRY_RELEASE: z.string().min(1).default('dev'),
});

// Next.js は process.env.NEXT_PUBLIC_… と1つずつ書いたものしか埋め込まないので、まとめて渡さない
export const clientEnv = parseEnv(ClientEnvSchema, {
  NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
  NEXT_PUBLIC_SENTRY_DSN: process.env.NEXT_PUBLIC_SENTRY_DSN,
  NEXT_PUBLIC_SENTRY_ENVIRONMENT: process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT,
  NEXT_PUBLIC_SENTRY_RELEASE: process.env.NEXT_PUBLIC_SENTRY_RELEASE,
});

import { parseEnv } from '@yumeguri/shared';
import { z } from 'zod';

// ブラウザに出してよい環境変数（NEXT_PUBLIC_ で始まるもの）。値は、ビルドのときにコードへ埋め込まれる
// 秘密の値はここに書かない。サーバーだけで使う値は、使い始めるときに serverEnv.ts（'server-only'）を作る
const ClientEnvSchema = z.object({
  NEXT_PUBLIC_API_URL: z.url(),
});

// Next.js は process.env.NEXT_PUBLIC_… と1つずつ書いたものしか埋め込まないので、まとめて渡さない
export const clientEnv = parseEnv(ClientEnvSchema, {
  NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
});

import { loadEnv } from 'vite';
import { defineConfig } from 'vitest/config';

// テストを2つに分ける
//   unit：DB などにつながない、ふつうのテスト（pnpm test）
//   integration：本物の PostgreSQL を使う結合テスト（*.int.test.ts。pnpm test:integration）
export default defineConfig({
  test: {
    projects: [
      {
        extends: true,
        test: {
          name: 'unit',
          include: ['src/**/*.test.ts'],
          exclude: ['src/**/*.int.test.ts'],
        },
      },
      {
        extends: true,
        test: {
          name: 'integration',
          include: ['src/**/*.int.test.ts'],
          // apps/api/.env（DATABASE_URL）を読む。CI には .env がないので、CI の環境変数がそのまま使われる
          env: loadEnv('', process.cwd(), ''),
        },
      },
    ],
  },
});

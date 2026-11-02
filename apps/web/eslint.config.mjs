import { defineConfig } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';
import rootConfig from '../../eslint.config.js';

// Next.js のルール（React・アクセシビリティ・画像など）に、リポジトリ共通のルールを重ねる
// ESLint 10 は、ファイルにいちばん近い設定だけを使うので、共通のルールもここで読み込む
export default defineConfig(...nextVitals, ...nextTs, ...rootConfig, {
  // リポジトリのいちばん上から ESLint を動かしても、Next.js のアプリの場所が分かるようにする
  settings: { next: { rootDir: import.meta.dirname } },
});

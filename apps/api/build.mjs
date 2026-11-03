// 本番用に、API を1つのファイル（dist/index.js）にまとめる（pnpm --filter @yumeguri/api build）
// packages/shared の .ts、Prisma Client、npm の部品も全部入るので、動かすときに node_modules が要らない
import { build } from 'esbuild';

await build({
  entryPoints: ['src/index.ts'],
  outfile: 'dist/index.js',
  bundle: true,
  platform: 'node',
  target: 'node24',
  format: 'esm',
  // エラーのスタックトレースを、まとめる前の .ts の行で出すため（node --enable-source-maps）
  sourcemap: true,
  // 元のソースの中身は .map に入れない（行の対応だけで足りる。.map が小さくなる）
  sourcesContent: false,
  // 古い形（CommonJS）の部品は require() を使う。ESM のファイルには require がないので、先頭で作っておく
  banner: {
    js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);",
  },
  logLevel: 'info',
});

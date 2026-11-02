import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// Prisma の CLI（マイグレーション・シード）の設定。表を作れるマイグレーション用の DB ユーザーでつなぐ
// （prisma generate は DB につながないので、MIGRATE_DATABASE_URL がなくても動く）
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    seed: 'tsx prisma/seed.ts',
  },
  datasource: {
    url: process.env['MIGRATE_DATABASE_URL'],
  },
});

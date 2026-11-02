import 'dotenv/config';
import { createPrismaClient } from '../apps/api/src/repositories/prismaClient';

// 開発用の架空のデータ。何回実行しても同じ結果になるように、ID を決めて upsert する
const url = process.env['MIGRATE_DATABASE_URL'];
if (!url) {
  throw new Error('MIGRATE_DATABASE_URL を .env に書いてください');
}
const prisma = createPrismaClient(url);

const ORGANIZATIONS = [
  { id: '019a4000-0000-7000-8000-000000000001', name: 'A 浴場組合', slug: 'a-bath-union' },
  { id: '019a4000-0000-7000-8000-000000000002', name: 'B 浴場組合', slug: 'b-bath-union' },
  { id: '019a4000-0000-7000-8000-000000000003', name: 'C 浴場組合', slug: 'c-bath-union' },
];
const PLATFORM_ADMIN_ID = '019a4000-0000-7000-8000-000000000101';

for (const org of ORGANIZATIONS) {
  await prisma.organization.upsert({ where: { id: org.id }, update: org, create: org });
}

await prisma.user.upsert({
  where: { id: PLATFORM_ADMIN_ID },
  update: {},
  create: {
    id: PLATFORM_ADMIN_ID,
    displayName: 'システム管理者',
    email: 'admin@example.com',
    platformRoles: { create: { role: 'platform_admin' } },
  },
});

await prisma.$disconnect();

// 結合テスト：本物の PostgreSQL で、マイグレーションが作った制約と権限が効いているかを確かめる
// （docs/erd.md の [SQL] の印のもの。モックでは確かめられない）
// 実行：pnpm --filter @yumeguri/api test:integration（apps/api/.env の DATABASE_URL：アプリ用の DB ユーザー）
// テストで入れたデータは、トランザクションごと取り消すので、DB に残らない
import { parseEnv } from '@yumeguri/shared';
import { afterAll, describe, expect, it } from 'vitest';
import { EnvSchema } from '../config/env';
import type { Prisma } from '../generated/prisma/client';
import { createPrismaClient, pingDatabase } from './prismaClient';

// API と同じ環境変数の決まりのうち、DB の接続先だけを使う
const { DATABASE_URL } = parseEnv(EnvSchema.pick({ DATABASE_URL: true }), process.env);
const prisma = createPrismaClient(DATABASE_URL);

afterAll(async () => {
  await prisma.$disconnect();
});

// テストの最後に投げて、トランザクションを取り消すための印
class Rollback extends Error {}

// fn の中で入れたデータを、最後に必ず取り消す。fn が投げたエラーは、そのまま返す
async function inRolledBackTransaction(
  fn: (tx: Prisma.TransactionClient) => Promise<void>,
): Promise<void> {
  await prisma
    .$transaction(async (tx) => {
      await fn(tx);
      throw new Rollback();
    })
    .catch((error: unknown) => {
      if (!(error instanceof Rollback)) throw error;
    });
}

describe('DB（本物の PostgreSQL）', () => {
  it('アプリ用の DB ユーザーで問い合わせができる（/readyz の中身）', async () => {
    await expect(pingDatabase(prisma)).resolves.toBeUndefined();
  });

  it('Membership：団体が食い違う「役割と銭湯」は、複合外部キーが断る', async () => {
    const attempt = inRolledBackTransaction(async (tx) => {
      const orgA = await tx.organization.create({ data: { name: 'テスト A', slug: 'test-a' } });
      const orgB = await tx.organization.create({ data: { name: 'テスト B', slug: 'test-b' } });
      const storeOfA = await tx.store.create({
        data: { organizationId: orgA.id, slug: 'test-a-store', name: 'テストの湯' },
      });
      const user = await tx.user.create({ data: { displayName: 'テストの人' } });

      // B 団体の役割なのに、A 団体の銭湯を指す
      await tx.membership.create({
        data: { userId: user.id, organizationId: orgB.id, storeId: storeOfA.id, role: 'staff' },
      });
    });

    await expect(attempt).rejects.toMatchObject({ code: 'P2003' });
  });

  it('Membership：同じ団体の銭湯なら入る', async () => {
    const attempt = inRolledBackTransaction(async (tx) => {
      const org = await tx.organization.create({ data: { name: 'テスト A', slug: 'test-a' } });
      const store = await tx.store.create({
        data: { organizationId: org.id, slug: 'test-a-store', name: 'テストの湯' },
      });
      const user = await tx.user.create({ data: { displayName: 'テストの人' } });

      await tx.membership.create({
        data: { userId: user.id, organizationId: org.id, storeId: store.id, role: 'staff' },
      });
    });

    await expect(attempt).resolves.toBeUndefined();
  });

  it('AuditLog：アプリ用の DB ユーザーは、書き換えられない（追記だけ）', async () => {
    const attempt = inRolledBackTransaction(async (tx) => {
      const log = await tx.auditLog.create({
        data: { action: 'test.action', targetType: 'Test', correlationId: 'test-cid' },
      });

      await tx.auditLog.update({ where: { id: log.id }, data: { action: 'test.changed' } });
    });

    await expect(attempt).rejects.toThrow(/permission denied/);
  });
});

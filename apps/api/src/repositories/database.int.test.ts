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

// 団体・その銭湯・利用者を1つずつ作る
async function createOrgStoreAndUser(tx: Prisma.TransactionClient) {
  const org = await tx.organization.create({ data: { name: 'テスト A', slug: 'test-a' } });
  const store = await tx.store.create({
    data: { organizationId: org.id, slug: 'test-a-store', name: 'テストの湯' },
  });
  const user = await tx.user.create({ data: { displayName: 'テストの人' } });
  return { org, store, user };
}

describe('DB（本物の PostgreSQL）', () => {
  it('アプリ用の DB ユーザーで問い合わせができる（/readyz の中身）', async () => {
    await expect(pingDatabase(prisma)).resolves.toBeUndefined();
  });

  it('Membership：団体が食い違う「役割と銭湯」は、複合外部キーが断る', async () => {
    const attempt = inRolledBackTransaction(async (tx) => {
      const { store: storeOfA, user } = await createOrgStoreAndUser(tx);
      const orgB = await tx.organization.create({ data: { name: 'テスト B', slug: 'test-b' } });

      // B 団体の役割なのに、A 団体の銭湯を指す
      await tx.membership.create({
        data: { userId: user.id, organizationId: orgB.id, storeId: storeOfA.id, role: 'staff' },
      });
    });

    await expect(attempt).rejects.toMatchObject({ code: 'P2003' });
  });

  it('Membership：同じ団体の銭湯なら入る', async () => {
    const attempt = inRolledBackTransaction(async (tx) => {
      const { org, store, user } = await createOrgStoreAndUser(tx);

      await tx.membership.create({
        data: { userId: user.id, organizationId: org.id, storeId: store.id, role: 'staff' },
      });
    });

    await expect(attempt).resolves.toBeUndefined();
  });

  describe('Visit', () => {
    // 団体・銭湯・利用者を作り、その人がその銭湯に QR で来た来訪のデータを返す（overrides で一部を変える）
    async function setUpVisit(
      tx: Prisma.TransactionClient,
      overrides: Partial<Prisma.VisitUncheckedCreateInput> = {},
    ): Promise<Prisma.VisitUncheckedCreateInput> {
      const { org, store, user } = await createOrgStoreAndUser(tx);
      return {
        userId: user.id,
        storeId: store.id,
        organizationId: org.id,
        visitedOn: new Date('2026-11-04'),
        source: 'qr',
        ...overrides,
      };
    }

    it('同じ人・同じ日・同じ銭湯の2件目は、部分一意インデックスが断る', async () => {
      const attempt = inRolledBackTransaction(async (tx) => {
        const visit = await setUpVisit(tx);

        await tx.visit.create({ data: visit });
        await tx.visit.create({ data: visit });
      });

      await expect(attempt).rejects.toMatchObject({ code: 'P2002' });
    });

    it('取り消したあとは、同じ日にもう一度入る', async () => {
      const attempt = inRolledBackTransaction(async (tx) => {
        const visit = await setUpVisit(tx);

        const first = await tx.visit.create({ data: visit });
        await tx.visit.update({ where: { id: first.id }, data: { revokedAt: new Date() } });
        await tx.visit.create({ data: visit });
      });

      await expect(attempt).resolves.toBeUndefined();
    });

    it('団体が食い違う来訪は、複合外部キーが断る', async () => {
      const attempt = inRolledBackTransaction(async (tx) => {
        const orgB = await tx.organization.create({ data: { name: 'テスト B', slug: 'test-b' } });
        // B 団体の来訪なのに、A 団体の銭湯を指す
        const visit = await setUpVisit(tx, { organizationId: orgB.id });

        await tx.visit.create({ data: visit });
      });

      await expect(attempt).rejects.toMatchObject({ code: 'P2003' });
    });

    it('手動の来訪は、付けたスタッフがないと CHECK 制約が断る', async () => {
      const attempt = inRolledBackTransaction(async (tx) => {
        const visit = await setUpVisit(tx, { source: 'manual' });

        await tx.visit.create({ data: visit });
      });

      await expect(attempt).rejects.toThrow(/Visit_manual_has_created_by_check/);
    });
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

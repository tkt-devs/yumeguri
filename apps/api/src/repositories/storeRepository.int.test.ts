// 結合テスト：本物の PostgreSQL で、銭湯の一覧・詳細の問い合わせを確かめる
// テストで入れたデータは、トランザクションごと取り消すので、DB に残らない
import { PrismaPg } from '@prisma/adapter-pg';
import { parseEnv } from '@yumeguri/shared';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { EnvSchema } from '../config/env';
import type { StoreListPosition } from '../domain/store';
import { PrismaClient, type Prisma } from '../generated/prisma/client';
import { toDbTime } from '../utils/dbTime';
import { PrismaStoreRepository } from './storeRepository';

const { DATABASE_URL } = parseEnv(EnvSchema.pick({ DATABASE_URL: true }), process.env);

// 発行された SQL を数えるために、クエリのイベントを受け取る
const prisma = new PrismaClient({
  adapter: new PrismaPg({ connectionString: DATABASE_URL }),
  log: [{ emit: 'event', level: 'query' }],
});
const queries: string[] = [];
prisma.$on('query', (event) => queries.push(event.query));

beforeEach(() => {
  queries.length = 0;
});
afterAll(async () => {
  await prisma.$disconnect();
});

class Rollback extends Error {}

// 既にある銭湯（シード）を見えなくしてから fn を動かし、最後に全部を取り消す
async function inIsolatedTransaction(
  fn: (tx: Prisma.TransactionClient, organizationId: string) => Promise<void>,
): Promise<void> {
  await prisma
    .$transaction(
      async (tx) => {
        await tx.store.updateMany({ data: { status: 'draft' } });
        const org = await tx.organization.create({
          data: { name: 'テスト', slug: 'store-repository-test' },
        });
        await fn(tx, org.id);
        throw new Rollback();
      },
      { timeout: 20_000 },
    )
    .catch((error: unknown) => {
      if (!(error instanceof Rollback)) throw error;
    });
}

const selectCount = () => queries.filter((query) => query.trimStart().startsWith('SELECT')).length;

describe('PrismaStoreRepository.listPublished', () => {
  it('公開中で消されていない銭湯だけを、名前の順に返す', async () => {
    await inIsolatedTransaction(async (tx, organizationId) => {
      const base = { organizationId };
      await tx.store.createMany({
        data: [
          { ...base, slug: 'test-b', name: 'テストB', status: 'published' },
          { ...base, slug: 'test-a', name: 'テストA', status: 'published' },
          { ...base, slug: 'test-draft', name: 'テスト下書き', status: 'draft' },
          { ...base, slug: 'test-closed', name: 'テスト閉業', status: 'closed' },
          {
            ...base,
            slug: 'test-deleted',
            name: 'テスト削除',
            status: 'published',
            deletedAt: new Date(),
          },
        ],
      });

      const rows = await new PrismaStoreRepository(tx).listPublished({
        take: 10,
        after: undefined,
      });

      expect(rows.map((row) => row.slug)).toEqual(['test-a', 'test-b']);
    });
  });

  it('同じ名前の銭湯があっても、ページ送りで重複も抜けも出ない', async () => {
    await inIsolatedTransaction(async (tx, organizationId) => {
      await tx.store.createMany({
        data: [1, 2, 3, 4, 5].map((n) => ({
          organizationId,
          slug: `same-name-${n}`,
          name: '同じ名前の湯',
          status: 'published' as const,
        })),
      });
      const repository = new PrismaStoreRepository(tx);

      const seen: string[] = [];
      let after: StoreListPosition | undefined;
      for (let page = 0; page < 5; page += 1) {
        const rows = await repository.listPublished({ take: 2, after });
        seen.push(...rows.map((row) => row.id));
        const last = rows.at(-1);
        if (!last) break;
        after = { name: last.name, id: last.id };
      }

      expect(seen).toHaveLength(5);
      expect(new Set(seen).size).toBe(5);
    });
  });

  it('写真は、準備完了のうち並び順が一番前のものを選ぶ', async () => {
    await inIsolatedTransaction(async (tx, organizationId) => {
      const store = await tx.store.create({
        data: { organizationId, slug: 'test-photo', name: 'テスト写真', status: 'published' },
      });
      await tx.photo.createMany({
        data: [
          { storeId: store.id, originalKey: 'o0', status: 'processing', sortOrder: 0 },
          {
            storeId: store.id,
            originalKey: 'o2',
            thumbnailKey: 't2',
            status: 'ready',
            sortOrder: 2,
          },
          {
            storeId: store.id,
            originalKey: 'o1',
            thumbnailKey: 't1',
            status: 'ready',
            sortOrder: 1,
          },
        ],
      });

      const [row] = await new PrismaStoreRepository(tx).listPublished({
        take: 10,
        after: undefined,
      });

      expect(row?.thumbnailKey).toBe('t1');
    });
  });

  it('N+1 がない：銭湯が 20 軒でも、SELECT は 2 回', async () => {
    await inIsolatedTransaction(async (tx, organizationId) => {
      for (let n = 0; n < 20; n += 1) {
        await tx.store.create({
          data: {
            organizationId,
            slug: `n-plus-one-${n}`,
            name: `N+1 の湯 ${String(n).padStart(2, '0')}`,
            status: 'published',
            photos: {
              create: { originalKey: `o${n}`, thumbnailKey: `t${n}`, status: 'ready' },
            },
          },
        });
      }
      queries.length = 0;

      const rows = await new PrismaStoreRepository(tx).listPublished({
        take: 20,
        after: undefined,
      });

      expect(rows).toHaveLength(20);
      expect(rows.every((row) => row.thumbnailKey !== null)).toBe(true);
      expect(selectCount()).toBe(2);
    });
  });
});

describe('PrismaStoreRepository.findPublicBySlug', () => {
  it('営業時間は曜日・開店の順、写真は準備完了だけを並び順で返す', async () => {
    await inIsolatedTransaction(async (tx, organizationId) => {
      const store = await tx.store.create({
        data: {
          organizationId,
          slug: 'test-detail',
          name: 'テスト詳細',
          status: 'closed',
          prices: { adult: 520, child: 200 },
        },
      });
      await tx.businessHour.createMany({
        data: [
          {
            storeId: store.id,
            weekday: 2,
            opensAt: toDbTime('15:00'),
            closesAt: toDbTime('01:00'),
          },
          {
            storeId: store.id,
            weekday: 1,
            opensAt: toDbTime('15:00'),
            closesAt: toDbTime('23:00'),
          },
          {
            storeId: store.id,
            weekday: 1,
            opensAt: toDbTime('06:00'),
            closesAt: toDbTime('09:00'),
          },
        ],
      });
      await tx.photo.createMany({
        data: [
          {
            storeId: store.id,
            originalKey: 'o2',
            thumbnailKey: 't2',
            status: 'ready',
            sortOrder: 2,
          },
          {
            storeId: store.id,
            originalKey: 'o1',
            thumbnailKey: 't1',
            status: 'ready',
            sortOrder: 1,
          },
          { storeId: store.id, originalKey: 'o3', status: 'failed', sortOrder: 0 },
        ],
      });
      queries.length = 0;

      const detail = await new PrismaStoreRepository(tx).findPublicBySlug('test-detail');

      expect(detail?.status).toBe('closed');
      expect(detail?.prices).toEqual({ adult: 520, child: 200 });
      expect(detail?.businessHours).toEqual([
        { weekday: 1, opensAt: '06:00', closesAt: '09:00' },
        { weekday: 1, opensAt: '15:00', closesAt: '23:00' },
        { weekday: 2, opensAt: '15:00', closesAt: '01:00' },
      ]);
      expect(detail?.photos.map((photo) => photo.thumbnailKey)).toEqual(['t1', 't2']);
      // 銭湯・営業時間・写真で、多くても 3 回
      expect(selectCount()).toBeLessThanOrEqual(3);
    });
  });

  it('下書き・消された銭湯・ない slug は null', async () => {
    await inIsolatedTransaction(async (tx, organizationId) => {
      await tx.store.createMany({
        data: [
          { organizationId, slug: 'test-hidden-draft', name: '下書き', status: 'draft' },
          {
            organizationId,
            slug: 'test-hidden-deleted',
            name: '削除',
            status: 'published',
            deletedAt: new Date(),
          },
        ],
      });
      const repository = new PrismaStoreRepository(tx);

      await expect(repository.findPublicBySlug('test-hidden-draft')).resolves.toBeNull();
      await expect(repository.findPublicBySlug('test-hidden-deleted')).resolves.toBeNull();
      await expect(repository.findPublicBySlug('test-missing')).resolves.toBeNull();
    });
  });
});

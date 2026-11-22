import { StoreDetailResponse, StorePrices } from '@yumeguri/shared';
import { z } from 'zod';
import type { PublicStoreDetail, PublishedStoreSummary, StoreListPosition } from '../domain/store';
import type { Prisma } from '../generated/prisma/client';
import { fromDbTime } from '../utils/dbTime';

// 生の SQL の結果は型が保証されないので、Zod で検証する
const FirstPhotoRows = z.array(z.object({ storeId: z.uuid(), thumbnailKey: z.string() }));

export type ListPublishedQuery = {
  take: number;
  after: StoreListPosition | undefined;
};

export interface StoreRepository {
  listPublished(query: ListPublishedQuery): Promise<PublishedStoreSummary[]>;
  findPublicBySlug(slug: string): Promise<PublicStoreDetail | null>;
}

// トランザクションの中でも使えるように、TransactionClient を受け取る（PrismaClient もそのまま渡せる）
export class PrismaStoreRepository implements StoreRepository {
  constructor(private readonly db: Prisma.TransactionClient) {}

  async listPublished({ take, after }: ListPublishedQuery): Promise<PublishedStoreSummary[]> {
    const stores = await this.db.store.findMany({
      where: {
        status: 'published',
        deletedAt: null,
        // 「名前が後ろ」または「名前が同じで id が後ろ」。名前が同じ銭湯も、重複も抜けもなく続く
        ...(after
          ? {
              // name >= は結果を変えないが、これがあると DB が索引のカーソルの位置から読み始められる
              name: { gte: after.name },
              OR: [{ name: { gt: after.name } }, { name: after.name, id: { gt: after.id } }],
            }
          : {}),
      },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
      take,
      select: { id: true, slug: true, name: true },
    });
    if (stores.length === 0) return [];

    // N+1 を防ぐ：銭湯ごとに問い合わせず、全部の銭湯の写真を1回で取る
    // DISTINCT ON で、DB が銭湯ごとに先頭の1枚だけを返す（Prisma の distinct は全部の写真を読んでからアプリで絞る）
    const storeIds = stores.map((store) => store.id);
    const photos = FirstPhotoRows.parse(
      await this.db.$queryRaw`
        SELECT DISTINCT ON (store_id) store_id AS "storeId", thumbnail_key AS "thumbnailKey"
        FROM "Photo"
        WHERE store_id = ANY(${storeIds}::uuid[]) AND status = 'ready'
        ORDER BY store_id, sort_order, id
      `,
    );
    const thumbnailKeys = new Map(photos.map((photo) => [photo.storeId, photo.thumbnailKey]));

    return stores.map((store) => ({
      ...store,
      thumbnailKey: thumbnailKeys.get(store.id) ?? null,
    }));
  }

  async findPublicBySlug(slug: string): Promise<PublicStoreDetail | null> {
    const store = await this.db.store.findFirst({
      where: { slug, deletedAt: null, status: { in: ['published', 'closed'] } },
      select: {
        id: true,
        slug: true,
        name: true,
        nameKana: true,
        description: true,
        prices: true,
        status: true,
        businessHours: {
          orderBy: [{ weekday: 'asc' }, { opensAt: 'asc' }],
          select: { weekday: true, opensAt: true, closesAt: true },
        },
        photos: {
          where: { status: 'ready' },
          orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
          select: { id: true, thumbnailKey: true, width: true, height: true },
        },
      },
    });
    if (!store) return null;

    // where で絞っているので、ここで違反が見つかれば DB の異常。隠さずに 500 にする
    return {
      ...store,
      // DB の JSON の列は型が保証されないので、ここで検証する
      prices: store.prices === null ? null : StorePrices.parse(store.prices),
      status: StoreDetailResponse.shape.status.parse(store.status),
      businessHours: store.businessHours.map((hour) => ({
        weekday: hour.weekday,
        opensAt: fromDbTime(hour.opensAt),
        closesAt: fromDbTime(hour.closesAt),
      })),
      // 準備完了の写真には、DB の CHECK 制約でサムネイルが必ずある
      photos: store.photos.map((photo) => ({
        ...photo,
        thumbnailKey: z.string().parse(photo.thumbnailKey),
      })),
    };
  }
}

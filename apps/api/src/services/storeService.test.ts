import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NotFoundError, ValidationError } from '../errors/appError';
import type { PublishedStoreSummary } from '../domain/store';
import type { StoreRepository } from '../repositories/storeRepository';
import { StoreService } from './storeService';

const IMAGE_BASE_URL = 'https://img.example.com';

const UME: PublishedStoreSummary = {
  id: '019a4000-0000-7000-8000-000000000201',
  slug: 'ume-no-yu',
  name: '梅の湯',
  thumbnailKey: 'stores/ume/a1.webp',
};
const SAKURA: PublishedStoreSummary = {
  id: '019a4000-0000-7000-8000-000000000202',
  slug: 'sakura-no-yu',
  name: '桜の湯',
  thumbnailKey: null,
};
const MATSU: PublishedStoreSummary = {
  id: '019a4000-0000-7000-8000-000000000203',
  slug: 'matsu-no-yu',
  name: '松の湯',
  thumbnailKey: 'stores/matsu/c1.webp',
};

// カーソルの中身（docs/api.md）：最後の行の名前（n）と id（i）を JSON にして、base64url にしたもの
const encodeCursor = (value: unknown) =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

describe('StoreService.listPublic', () => {
  const listPublished = vi.fn<StoreRepository['listPublished']>();
  const findPublicBySlug = vi.fn<StoreRepository['findPublicBySlug']>();
  const service = new StoreService({ listPublished, findPublicBySlug }, IMAGE_BASE_URL);

  beforeEach(() => {
    listPublished.mockReset();
  });

  it('次のページの有無を調べるため、DB には「件数 + 1」行を頼む', async () => {
    listPublished.mockResolvedValue([UME]);

    await service.listPublic({ limit: 2 });

    expect(listPublished).toHaveBeenCalledWith({ take: 3, after: undefined });
  });

  it('続きがなければ、全部の行を返し、nextCursor は null', async () => {
    listPublished.mockResolvedValue([UME, SAKURA]);

    const page = await service.listPublic({ limit: 2 });

    expect(page.items.map((item) => item.name)).toEqual(['梅の湯', '桜の湯']);
    expect(page.nextCursor).toBeNull();
  });

  it('続きがあれば、余分な1行を返さず、最後に返す行を nextCursor にする', async () => {
    listPublished.mockResolvedValue([UME, SAKURA, MATSU]);

    const page = await service.listPublic({ limit: 2 });

    expect(page.items.map((item) => item.name)).toEqual(['梅の湯', '桜の湯']);
    expect(page.nextCursor).toBe(encodeCursor({ n: SAKURA.name, i: SAKURA.id }));
  });

  it('カーソルを、名前と id に戻して Repository に渡す', async () => {
    listPublished.mockResolvedValue([MATSU]);

    await service.listPublic({
      limit: 2,
      cursor: encodeCursor({ n: SAKURA.name, i: SAKURA.id }),
    });

    expect(listPublished).toHaveBeenCalledWith({
      take: 3,
      after: { name: SAKURA.name, id: SAKURA.id },
    });
  });

  it('名前が空の銭湯のカーソルも受け付ける（API が自分で出した値を断らない）', async () => {
    listPublished.mockResolvedValue([]);

    await service.listPublic({ limit: 2, cursor: encodeCursor({ n: '', i: SAKURA.id }) });

    expect(listPublished).toHaveBeenCalledWith({ take: 3, after: { name: '', id: SAKURA.id } });
  });

  it.each([
    ['base64url として読めても JSON ではない', Buffer.from('not-json').toString('base64url')],
    ['名前がない', encodeCursor({ i: SAKURA.id })],
    ['id がない', encodeCursor({ n: SAKURA.name })],
    ['id が UUID ではない', encodeCursor({ n: SAKURA.name, i: 'abc' })],
    ['JSON の形が違う', encodeCursor(['梅の湯'])],
    ['名前に NUL 文字がある', encodeCursor({ n: 'a\u0000b', i: SAKURA.id })],
  ])('壊れたカーソル（%s）は ValidationError にして、DB を呼ばない', async (_name, cursor) => {
    await expect(service.listPublic({ limit: 2, cursor })).rejects.toThrow(ValidationError);
    expect(listPublished).not.toHaveBeenCalled();
  });

  it('写真のキーを画像の URL に変え、写真がなければ null にする', async () => {
    listPublished.mockResolvedValue([UME, SAKURA]);

    const page = await service.listPublic({ limit: 2 });

    expect(page.items).toEqual([
      {
        id: UME.id,
        slug: UME.slug,
        name: UME.name,
        thumbnailUrl: 'https://img.example.com/stores/ume/a1.webp',
      },
      { id: SAKURA.id, slug: SAKURA.slug, name: SAKURA.name, thumbnailUrl: null },
    ]);
  });
});

describe('StoreService.getPublicBySlug', () => {
  const listPublished = vi.fn<StoreRepository['listPublished']>();
  const findPublicBySlug = vi.fn<StoreRepository['findPublicBySlug']>();
  const service = new StoreService({ listPublished, findPublicBySlug }, IMAGE_BASE_URL);

  beforeEach(() => {
    findPublicBySlug.mockReset();
  });

  it('写真のキーを画像の URL に変えて返す', async () => {
    findPublicBySlug.mockResolvedValue({
      id: UME.id,
      slug: UME.slug,
      name: UME.name,
      nameKana: 'うめのゆ',
      description: null,
      prices: { adult: 520 },
      status: 'published',
      businessHours: [{ weekday: 1, opensAt: '15:00', closesAt: '01:00' }],
      photos: [{ id: MATSU.id, thumbnailKey: 'stores/ume/a1.webp', width: 1200, height: 800 }],
    });

    const store = await service.getPublicBySlug('ume-no-yu');

    expect(store.photos).toEqual([
      { id: MATSU.id, url: 'https://img.example.com/stores/ume/a1.webp', width: 1200, height: 800 },
    ]);
  });

  it('見つからなければ NotFoundError', async () => {
    findPublicBySlug.mockResolvedValue(null);

    await expect(service.getPublicBySlug('no-such-store')).rejects.toThrow(NotFoundError);
  });

  it.each(['Ume', 'ume_no_yu', 'a\u0000b', '-ume', 'a'.repeat(101)])(
    'slug の形でない文字列（%j）は、DB を呼ばずに NotFoundError',
    async (slug) => {
      await expect(service.getPublicBySlug(slug)).rejects.toThrow(NotFoundError);
      expect(findPublicBySlug).not.toHaveBeenCalled();
    },
  );
});

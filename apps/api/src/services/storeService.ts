import type { CursorPageQuery, StoreDetailResponse, StoreListResponse } from '@yumeguri/shared';
import { NotFoundError, ValidationError } from '../errors/appError';
import type { StoreRepository } from '../repositories/storeRepository';
import { decodeStoreCursor, encodeStoreCursor } from '../utils/storeCursor';

// slug の形。これ以外の文字列（NUL 文字など）は、DB に問い合わせずに「ない」とする
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SLUG_MAX_LENGTH = 100;

// 公開の銭湯の業務のルール（だれでも見られるので、権限の判定はない）
export class StoreService {
  constructor(
    private readonly stores: StoreRepository,
    private readonly imageBaseUrl: string,
  ) {}

  async listPublic({ limit, cursor }: CursorPageQuery): Promise<StoreListResponse> {
    const after = cursor === undefined ? undefined : decodeStoreCursor(cursor);
    if (after === null) {
      throw new ValidationError([{ path: 'cursor', message: 'カーソルが正しくありません' }]);
    }

    // 1行多く頼み、返ってきたら「次のページがある」と分かる（件数を数える SQL が要らない）
    const rows = await this.stores.listPublished({ take: limit + 1, after });
    // 続きがあるときだけ、実際に返す最後の行を次のページの起点にする
    const last = rows.length > limit ? rows[limit - 1] : undefined;

    return {
      items: rows.slice(0, limit).map((row) => ({
        id: row.id,
        slug: row.slug,
        name: row.name,
        thumbnailUrl: row.thumbnailKey === null ? null : this.imageUrl(row.thumbnailKey),
      })),
      nextCursor: last ? encodeStoreCursor(last) : null,
    };
  }

  async getPublicBySlug(slug: string): Promise<StoreDetailResponse> {
    if (slug.length > SLUG_MAX_LENGTH || !SLUG_PATTERN.test(slug)) {
      throw new NotFoundError();
    }
    const store = await this.stores.findPublicBySlug(slug);
    // ない・下書き・消されている銭湯は、区別せずに 404 にする（存在を教えない）
    if (!store) throw new NotFoundError();

    return {
      ...store,
      photos: store.photos.map(({ id, thumbnailKey, width, height }) => ({
        id,
        url: this.imageUrl(thumbnailKey),
        width,
        height,
      })),
    };
  }

  private imageUrl(key: string): string {
    return `${this.imageBaseUrl}/${key}`;
  }
}

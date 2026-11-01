import { z } from 'zod';

// 一覧の件数（docs/api.md：初期値 20、上限 50）
export const PAGE_LIMIT_DEFAULT = 20;
export const PAGE_LIMIT_MAX = 50;

// 一覧のリクエストの ?limit=&cursor=（クエリは文字列で来るので、数に直してから検証する）
export const cursorPageQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(PAGE_LIMIT_MAX).default(PAGE_LIMIT_DEFAULT),
  cursor: z.string().min(1).optional(),
});
export type CursorPageQuery = z.infer<typeof cursorPageQuerySchema>;

// 一覧のレスポンス。次のページがなければ nextCursor は null
export type CursorPage<T> = {
  items: T[];
  nextCursor: string | null;
};

export function cursorPageSchema<T extends z.ZodType>(item: T) {
  return z.object({
    items: z.array(item),
    nextCursor: z.string().nullable(),
  });
}

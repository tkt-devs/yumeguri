import { z } from 'zod';
import { cursorPageSchema } from './pagination';

// 公開の銭湯の API のレスポンス（docs/api.md の 4・5）。画面と API で同じ形を使う

export const StoreListItemResponse = z.object({
  id: z.uuid(),
  slug: z.string(),
  name: z.string(),
  // 並び順が一番前の、準備完了の写真。なければ null
  thumbnailUrl: z.url().nullable(),
});
export type StoreListItemResponse = z.infer<typeof StoreListItemResponse>;

export const StoreListResponse = cursorPageSchema(StoreListItemResponse);
export type StoreListResponse = z.infer<typeof StoreListResponse>;

// 料金。例：{"adult": 520, "child": 200}
export const StorePrices = z.record(z.string(), z.number().int().nonnegative());
export type StorePrices = z.infer<typeof StorePrices>;

// 時刻（HH:MM、00:00〜23:59）
export const TimeOfDay = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);

export const StoreDetailResponse = z.object({
  id: z.uuid(),
  slug: z.string(),
  name: z.string(),
  nameKana: z.string().nullable(),
  description: z.string().nullable(),
  prices: StorePrices.nullable(),
  // 閉業した銭湯も、ページに「閉業しました」と出すために返す
  status: z.enum(['published', 'closed']),
  // closesAt が opensAt より小さければ、日付をまたぐ。行がない曜日は定休日
  businessHours: z.array(
    z.object({
      weekday: z.number().int().min(0).max(6),
      opensAt: TimeOfDay,
      closesAt: TimeOfDay,
    }),
  ),
  photos: z.array(
    z.object({
      id: z.uuid(),
      url: z.url(),
      width: z.number().int().positive().nullable(),
      height: z.number().int().positive().nullable(),
    }),
  ),
});
export type StoreDetailResponse = z.infer<typeof StoreDetailResponse>;

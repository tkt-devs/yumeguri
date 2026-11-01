import { z } from 'zod';
import { describe, expect, it } from 'vitest';
import { cursorPageQuerySchema, cursorPageSchema } from './pagination';

describe('cursorPageQuerySchema', () => {
  it('limit がなければ 20 にする', () => {
    expect(cursorPageQuerySchema.parse({})).toEqual({ limit: 20 });
  });

  it('クエリの文字列の limit を数に直す', () => {
    expect(cursorPageQuerySchema.parse({ limit: '50', cursor: 'eyJu' })).toEqual({
      limit: 50,
      cursor: 'eyJu',
    });
  });

  it.each(['0', '51', '1.5', 'abc'])('limit=%s は受け付けない', (limit) => {
    expect(cursorPageQuerySchema.safeParse({ limit }).success).toBe(false);
  });
});

describe('cursorPageSchema', () => {
  const storePage = cursorPageSchema(z.object({ name: z.string() }));

  it('最後のページは nextCursor が null', () => {
    expect(storePage.safeParse({ items: [{ name: '梅の湯' }], nextCursor: null }).success).toBe(
      true,
    );
  });

  it('items の中身も検証する', () => {
    expect(storePage.safeParse({ items: [{ name: 1 }], nextCursor: null }).success).toBe(false);
  });
});

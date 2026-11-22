import { z } from 'zod';
import type { StoreListPosition } from '../domain/store';

// カーソルの中身（docs/api.md）。PostgreSQL の文字列には NUL 文字を入れられないので、ここで断る
const StoreCursorPayload = z.object({
  n: z.string().refine((value) => !value.includes('\u0000')),
  i: z.uuid(),
});

export function encodeStoreCursor(position: StoreListPosition): string {
  return Buffer.from(JSON.stringify({ n: position.name, i: position.id }), 'utf8').toString(
    'base64url',
  );
}

// カーソルは利用者が書き換えられる値なので、壊れていれば null を返す
export function decodeStoreCursor(cursor: string): StoreListPosition | null {
  let value: unknown;
  try {
    value = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  const parsed = StoreCursorPayload.safeParse(value);
  return parsed.success ? { name: parsed.data.n, id: parsed.data.i } : null;
}

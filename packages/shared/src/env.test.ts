import { z } from 'zod';
import { describe, expect, it } from 'vitest';
import { parseEnv } from './env';

const schema = z.object({
  DATABASE_URL: z.url(),
  PORT: z.coerce.number().int(),
});

describe('parseEnv', () => {
  it('正しい環境変数を、型の付いた値にして返す', () => {
    expect(
      parseEnv(schema, { DATABASE_URL: 'postgresql://localhost:5433/yumeguri', PORT: '3001' }),
    ).toEqual({
      DATABASE_URL: 'postgresql://localhost:5433/yumeguri',
      PORT: 3001,
    });
  });

  it('足りない・形が違うものを、全部まとめてエラーにする', () => {
    expect(() => parseEnv(schema, { PORT: 'abc' })).toThrow(/DATABASE_URL[\s\S]*PORT/);
  });

  it('エラーに値そのものを出さない', () => {
    const run = () => parseEnv(schema, { DATABASE_URL: 'secret-value', PORT: '3001' });
    expect(run).toThrow(/DATABASE_URL/);
    expect(run).not.toThrow(/secret-value/);
  });
});

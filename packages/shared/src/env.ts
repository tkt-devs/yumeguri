import { z } from 'zod';

// 起動時に環境変数を検証する。足りない・形が違うものがあれば、全部まとめて分かるエラーで止める。
// 値そのものはエラーに出さない（シークレットがログに残らないように）
export function parseEnv<T extends z.ZodType>(
  schema: T,
  source: Record<string, string | undefined>,
): z.infer<T> {
  const result = schema.safeParse(source);
  if (!result.success) {
    throw new Error(`環境変数が足りないか、形が違います。\n${z.prettifyError(result.error)}`);
  }
  return result.data;
}

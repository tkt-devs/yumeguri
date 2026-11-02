import { z } from 'zod';

// 相関 ID のヘッダーの名前（docs/api.md）。API が受け取り・返し、画面がエラーのときに表示する
export const CORRELATION_ID_HEADER = 'X-Correlation-Id';

// エラーコードの一覧（docs/api.md）。画面はこの code を見て表示を変える
export const ERROR_CODES = [
  'AUTH_REQUIRED',
  'FORBIDDEN',
  'NOT_FOUND',
  'VALIDATION_FAILED',
  'TOKEN_INVALID',
  'TOKEN_EXPIRED',
  'TOKEN_ALREADY_USED',
  'INTERNAL_ERROR',
  'SERVICE_UNAVAILABLE',
] as const;

export const errorCodeSchema = z.enum(ERROR_CODES);
export type ErrorCode = z.infer<typeof errorCodeSchema>;

// それぞれのエラーコードで返す HTTP のステータス
export const ERROR_STATUS = {
  AUTH_REQUIRED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  VALIDATION_FAILED: 422,
  TOKEN_INVALID: 400,
  TOKEN_EXPIRED: 400,
  TOKEN_ALREADY_USED: 409,
  INTERNAL_ERROR: 500,
  SERVICE_UNAVAILABLE: 503,
} as const satisfies Record<ErrorCode, number>;

// エラーのときの本文（RFC 9457 の Problem Details）
export const problemDetailsSchema = z.object({
  type: z.url(),
  title: z.string(),
  status: z.number().int(),
  code: errorCodeSchema,
  correlationId: z.string(),
  // 入力のエラー（VALIDATION_FAILED）のときだけ
  errors: z.array(z.object({ path: z.string(), message: z.string() })).optional(),
});
export type ProblemDetails = z.infer<typeof problemDetailsSchema>;

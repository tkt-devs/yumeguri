import {
  CORRELATION_ID_HEADER,
  problemDetailsSchema,
  type ErrorCode,
  type ProblemDetails,
} from '@yumeguri/shared';

// API がエラーを返したときに投げるエラー。画面は code を見て表示を変える（title の文章で判定しない）
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    readonly correlationId: string | null,
    readonly errors: ProblemDetails['errors'],
    message: string,
  ) {
    super(message);
  }
}

// エラーのレスポンス（problem+json）を ApiError にする
export async function toApiError(res: Response): Promise<ApiError> {
  const body: unknown = await res.json().catch(() => null);
  const problem = problemDetailsSchema.safeParse(body);
  if (problem.success) {
    const { code, correlationId, errors, title } = problem.data;
    return new ApiError(res.status, code, correlationId, errors, title);
  }
  // problem+json ではない（API の手前で止まった、など）
  return new ApiError(
    res.status,
    'INTERNAL_ERROR',
    res.headers.get(CORRELATION_ID_HEADER),
    undefined,
    'API から予期しない応答がありました',
  );
}

import type { ErrorCode, ProblemDetails } from '@yumeguri/shared';

type FieldError = NonNullable<ProblemDetails['errors']>[number];

// 業務のエラー。HTTP のステータスは code から決まる（@yumeguri/shared の ERROR_STATUS）
export class AppError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    // 入力のエラー（VALIDATION_FAILED）のときだけ、どの項目がだめかを持つ
    readonly errors?: FieldError[],
  ) {
    super(message);
  }
}

export class NotFoundError extends AppError {
  constructor() {
    super('NOT_FOUND', '見つかりません');
  }
}

export class ForbiddenError extends AppError {
  constructor() {
    super('FORBIDDEN', 'この操作はできません');
  }
}

export class ValidationError extends AppError {
  constructor(errors: FieldError[]) {
    super('VALIDATION_FAILED', '入力の内容を確かめてください', errors);
  }
}

export class ServiceUnavailableError extends AppError {
  constructor() {
    super('SERVICE_UNAVAILABLE', '一時的に利用できません');
  }
}

export class InternalError extends AppError {
  constructor() {
    super('INTERNAL_ERROR', '時間をおいて、もう一度お試しください');
  }
}

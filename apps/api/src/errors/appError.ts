import type { ErrorCode } from '@yumeguri/shared';

// 業務のエラー。HTTP のステータスは code から決まる（@yumeguri/shared の ERROR_STATUS）
export class AppError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
  }
}

export class NotFoundError extends AppError {
  constructor() {
    super('NOT_FOUND', '見つかりません');
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

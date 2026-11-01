import { describe, expect, it } from 'vitest';
import { ERROR_CODES, ERROR_STATUS, problemDetailsSchema } from './errors';

describe('ERROR_STATUS', () => {
  it('すべてのエラーコードに HTTP のステータスがある', () => {
    for (const code of ERROR_CODES) {
      expect(ERROR_STATUS[code]).toBeGreaterThanOrEqual(400);
    }
  });
});

describe('problemDetailsSchema', () => {
  const validationFailed = {
    type: 'https://api.sento-stamprally.com/problems/validation-failed',
    title: '入力に誤りがあります',
    status: 422,
    code: 'VALIDATION_FAILED',
    correlationId: '01JC8Z',
    errors: [{ path: 'businessHours.0.opensAt', message: 'HH:MM の形で入力してください' }],
  };

  it('docs/api.md の例を受け付ける', () => {
    expect(problemDetailsSchema.safeParse(validationFailed).success).toBe(true);
  });

  it('errors がなくても受け付ける', () => {
    const notFound = {
      type: 'https://api.sento-stamprally.com/problems/not-found',
      title: '見つかりません',
      status: 404,
      code: 'NOT_FOUND',
      correlationId: '01JC8Z',
    };
    expect(problemDetailsSchema.safeParse(notFound).success).toBe(true);
  });

  it('一覧にないエラーコードは受け付けない', () => {
    expect(
      problemDetailsSchema.safeParse({ ...validationFailed, code: 'ALREADY_CHECKED_IN' }).success,
    ).toBe(false);
  });
});

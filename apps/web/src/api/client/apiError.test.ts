import { describe, expect, it } from 'vitest';
import { ApiError, toApiError } from './apiError';

const problem = {
  type: 'https://api.sento-stamprally.com/problems/service-unavailable',
  title: '一時的に利用できません',
  status: 503,
  code: 'SERVICE_UNAVAILABLE',
  correlationId: 'c-1',
};

describe('toApiError', () => {
  it('problem+json を、code と相関 ID の付いた ApiError にする', async () => {
    const res = new Response(JSON.stringify(problem), { status: 503 });
    const err = await toApiError(res);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).toMatchObject({ status: 503, code: 'SERVICE_UNAVAILABLE', correlationId: 'c-1' });
  });

  it('problem+json でなければ INTERNAL_ERROR にして、ヘッダーの相関 ID を使う', async () => {
    const res = new Response('<html>Bad Gateway</html>', {
      status: 502,
      headers: { 'X-Correlation-Id': 'c-2' },
    });
    expect(await toApiError(res)).toMatchObject({
      status: 502,
      code: 'INTERNAL_ERROR',
      correlationId: 'c-2',
    });
  });
});

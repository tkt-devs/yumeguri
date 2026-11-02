import { afterEach, describe, expect, it, vi } from 'vitest';
import { CORRELATION_ID_HEADER, createApp } from './app';
import { createLogger } from './logger';
import { READINESS_CHECK_TIMEOUT_MS, type ReadinessCheck } from './services/readiness';

// ログを標準出力ではなく配列に入れて、中身を確かめる
function setup(readinessChecks: ReadinessCheck[] = []) {
  const logs: unknown[] = [];
  const logger = createLogger('info', { write: (line) => logs.push(JSON.parse(line)) });
  const app = createApp({ logger, readinessChecks });
  return { app, logs };
}

const ok: ReadinessCheck = { name: 'db', check: async () => {} };
const down: ReadinessCheck = {
  name: 'valkey',
  check: async () => {
    throw new Error('connect ECONNREFUSED');
  },
};

describe('GET /healthz', () => {
  it('いつも 200 を返す', async () => {
    const { app } = setup([down]);
    const res = await app.request('/healthz');
    expect(res.status).toBe(200);
  });
});

describe('GET /readyz', () => {
  it('全部につながれば 200 を返す', async () => {
    const { app } = setup([ok]);
    const res = await app.request('/readyz');
    expect(res.status).toBe(200);
  });

  it('1つでもつながらなければ 503 と SERVICE_UNAVAILABLE を返し、どれがだめかをログに出す', async () => {
    const { app, logs } = setup([ok, down]);
    const res = await app.request('/readyz');
    expect(res.status).toBe(503);
    expect(await res.json()).toMatchObject({ code: 'SERVICE_UNAVAILABLE' });
    expect(logs).toContainEqual(expect.objectContaining({ msg: 'not ready', failed: ['valkey'] }));
  });

  describe('時間', () => {
    afterEach(() => {
      vi.useRealTimers();
    });

    it('返ってこない相手がいても、待ち続けずに 503 を返す', async () => {
      vi.useFakeTimers();
      const hang: ReadinessCheck = { name: 'db', check: () => new Promise(() => {}) };
      const { app, logs } = setup([hang]);
      const pending = app.request('/readyz');
      await vi.advanceTimersByTimeAsync(READINESS_CHECK_TIMEOUT_MS);
      const res = await pending;
      expect(res.status).toBe(503);
      expect(logs).toContainEqual(expect.objectContaining({ msg: 'not ready', failed: ['db'] }));
    });
  });
});

describe('存在しないパス', () => {
  it('RFC 9457 の形の 404 を返す', async () => {
    const { app } = setup();
    const res = await app.request('/nothing');
    expect(res.status).toBe(404);
    expect(res.headers.get('Content-Type')).toBe('application/problem+json');
    expect(await res.json()).toEqual({
      type: 'https://api.sento-stamprally.com/problems/not-found',
      title: '見つかりません',
      status: 404,
      code: 'NOT_FOUND',
      correlationId: res.headers.get(CORRELATION_ID_HEADER),
    });
  });
});

describe('予期しないエラー', () => {
  it('500 と INTERNAL_ERROR を返し、例外のメッセージはレスポンスにもログにも出さない', async () => {
    const { app, logs } = setup();
    app.get('/boom', () => {
      throw new Error('password=secret-value');
    });
    const res = await app.request('/boom');
    expect(res.status).toBe(500);
    const body = await res.text();
    expect(JSON.parse(body)).toMatchObject({ code: 'INTERNAL_ERROR' });
    expect(body).not.toContain('secret-value');
    expect(JSON.stringify(logs)).not.toContain('secret-value');
    expect(logs).toContainEqual(expect.objectContaining({ msg: 'unexpected error' }));
  });

  it('メッセージが複数行でも、2行目以降もログに出さない', async () => {
    const { app, logs } = setup();
    app.get('/boom', () => {
      throw new Error('connect failed\nat postgresql://user:secret-value@db/yumeguri');
    });
    await app.request('/boom');
    expect(JSON.stringify(logs)).not.toContain('secret-value');
    // どこで起きたかは残っている
    expect(logs).toContainEqual(
      expect.objectContaining({ msg: 'unexpected error', stack: expect.stringContaining('at ') }),
    );
  });
});

describe('相関 ID', () => {
  it('送られてきた X-Correlation-Id を、レスポンスとログにそのまま使う', async () => {
    const { app, logs } = setup();
    const res = await app.request('/healthz', { headers: { [CORRELATION_ID_HEADER]: 'abc-123' } });
    expect(res.headers.get(CORRELATION_ID_HEADER)).toBe('abc-123');
    expect(logs).toContainEqual(
      expect.objectContaining({
        msg: 'request',
        correlationId: 'abc-123',
        method: 'GET',
        path: '/healthz',
        status: 200,
      }),
    );
  });

  it('送られてこなければ、新しく作る', async () => {
    const { app } = setup();
    const res = await app.request('/healthz');
    expect(res.headers.get(CORRELATION_ID_HEADER)).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('エラーのときも、レスポンスのヘッダー・本文・ログに同じ相関 ID が入る', async () => {
    const { app, logs } = setup();
    const res = await app.request('/nothing', { headers: { [CORRELATION_ID_HEADER]: 'err-1' } });
    expect(res.headers.get(CORRELATION_ID_HEADER)).toBe('err-1');
    expect(await res.json()).toMatchObject({ correlationId: 'err-1' });
    expect(logs).toContainEqual(
      expect.objectContaining({ msg: 'request', correlationId: 'err-1', status: 404 }),
    );
  });

  it('ログにクエリを出さない（QR のトークンなどが入るため）', async () => {
    const { app, logs } = setup();
    await app.request('/healthz?t=qr-token-value');
    expect(JSON.stringify(logs)).not.toContain('qr-token-value');
  });
});

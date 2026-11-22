import { afterEach, describe, expect, it, vi } from 'vitest';
import { CORRELATION_ID_HEADER } from '@yumeguri/shared';
import { createApp } from './app';
import { createLogger } from './logger';
import { READINESS_CHECK_TIMEOUT_MS, type ReadinessCheck } from './services/readiness';
import { StoreService } from './services/storeService';

const WEB_ORIGIN = 'http://localhost:3000';

// ログを標準出力ではなく配列に入れて、中身を確かめる
function setup(readinessChecks: ReadinessCheck[] = []) {
  const logs: unknown[] = [];
  const logger = createLogger('info', { write: (line) => logs.push(JSON.parse(line)) });
  const storeService = new StoreService(
    {
      listPublished: async () => [
        {
          id: '019a4000-0000-7000-8000-000000000201',
          slug: 'ume-no-yu',
          name: '梅の湯',
          thumbnailKey: null,
        },
      ],
      findPublicBySlug: async () => null,
    },
    'https://img.example.com',
  );
  const app = createApp({ logger, webOrigin: WEB_ORIGIN, readinessChecks, storeService });
  return { app, logs };
}

const ok: ReadinessCheck = { name: 'db', check: async () => {} };
const down: ReadinessCheck = {
  name: 'valkey',
  check: async () => {
    throw new Error('connect ECONNREFUSED');
  },
};

describe('GET /v1/stores', () => {
  it('ログインなしで 200 と一覧を返す', async () => {
    const { app } = setup();
    const res = await app.request('/v1/stores');
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({
      items: [{ slug: 'ume-no-yu', thumbnailUrl: null }],
      nextCursor: null,
    });
  });

  it.each(['limit=0', 'limit=51', 'limit=abc', 'cursor=broken'])(
    '%s は 422 と VALIDATION_FAILED を返し、どの項目かを示す',
    async (query) => {
      const { app } = setup();
      const res = await app.request(`/v1/stores?${query}`);
      expect(res.status).toBe(422);
      expect(await res.json()).toMatchObject({
        code: 'VALIDATION_FAILED',
        errors: [{ path: query.split('=')[0] }],
      });
    },
  );
});

describe('GET /v1/stores/:slug', () => {
  it('見つからなければ 404 と NOT_FOUND を返す', async () => {
    const { app } = setup();
    const res = await app.request('/v1/stores/no-such-store');
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ code: 'NOT_FOUND' });
  });
});

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

describe('CORS', () => {
  it('画面（WEB_ORIGIN）からの呼び出しを、Cookie 付きで許可する', async () => {
    const { app } = setup();
    const res = await app.request('/healthz', { headers: { Origin: WEB_ORIGIN } });
    expect(res.headers.get('Access-Control-Allow-Origin')).toBe(WEB_ORIGIN);
    expect(res.headers.get('Access-Control-Allow-Credentials')).toBe('true');
    expect(res.headers.get('Access-Control-Expose-Headers')).toContain(CORRELATION_ID_HEADER);
  });

  it('ほかの場所からの呼び出しは、許可しない', async () => {
    const { app } = setup();
    const res = await app.request('/healthz', { headers: { Origin: 'https://evil.example' } });
    expect(res.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('確認のリクエスト（OPTIONS）の答えを、10 分覚えさせる', async () => {
    const { app } = setup();
    const res = await app.request('/healthz', {
      method: 'OPTIONS',
      headers: { Origin: WEB_ORIGIN, 'Access-Control-Request-Method': 'POST' },
    });
    expect(res.status).toBe(204);
    expect(res.headers.get('Access-Control-Max-Age')).toBe('600');
  });
});

describe('CSRF（Origin の確認）', () => {
  it.each(['POST', 'PUT', 'PATCH', 'DELETE'])('%s：ほかのサイトからは 403', async (method) => {
    const { app } = setup();
    const res = await app.request('/healthz', {
      method,
      headers: { Origin: 'https://evil.example' },
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: 'FORBIDDEN' });
  });

  it('Origin がない POST も 403', async () => {
    const { app } = setup();
    const res = await app.request('/healthz', { method: 'POST' });
    expect(res.status).toBe(403);
  });

  it('よく似たドメインは通さない', async () => {
    const { app } = setup();
    const res = await app.request('/healthz', {
      method: 'POST',
      headers: { Origin: `${WEB_ORIGIN}.evil.example` },
    });
    expect(res.status).toBe(403);
  });

  it('画面からの POST は通す（この場所に POST の処理はないので 404）', async () => {
    const { app } = setup();
    const res = await app.request('/healthz', { method: 'POST', headers: { Origin: WEB_ORIGIN } });
    expect(res.status).toBe(404);
  });

  it('GET は Origin がなくても通す', async () => {
    const { app } = setup();
    const res = await app.request('/healthz');
    expect(res.status).toBe(200);
  });
});

describe('セキュリティヘッダー', () => {
  it.each([
    ['正常', '/healthz'],
    ['404', '/no-such-path'],
  ])('%s の返事にも付く', async (_name, path) => {
    const { app } = setup();
    const res = await app.request(path);
    expect(res.headers.get('Content-Security-Policy')).toContain("default-src 'none'");
    expect(res.headers.get('Content-Security-Policy')).toContain("frame-ancestors 'none'");
    expect(res.headers.get('Strict-Transport-Security')).toBe('max-age=15552000');
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(res.headers.get('Referrer-Policy')).toBe('no-referrer');
    expect(res.headers.get('Permissions-Policy')).toContain('camera=()');
  });
});

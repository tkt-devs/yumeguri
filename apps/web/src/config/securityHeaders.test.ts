import { describe, expect, it } from 'vitest';
import { buildContentSecurityPolicy, buildSecurityHeaders } from './securityHeaders';

const base = { apiUrl: 'https://api.example.com/v1', isDev: false };

describe('buildContentSecurityPolicy', () => {
  it('通信してよい相手に、API のオリジンを入れる', () => {
    expect(buildContentSecurityPolicy(base)).toContain(
      "connect-src 'self' https://api.example.com;",
    );
  });

  it('Sentry の受け口を入れ、DSN の鍵は入れない', () => {
    const csp = buildContentSecurityPolicy({
      ...base,
      sentryDsn: 'https://publickey@o1.ingest.sentry.io/2',
    });
    expect(csp).toContain('https://o1.ingest.sentry.io');
    expect(csp).not.toContain('publickey');
  });

  it('本番のビルドでは unsafe-eval を許さない', () => {
    const csp = buildContentSecurityPolicy(base);
    expect(csp).not.toContain('unsafe-eval');
    expect(csp).toContain('upgrade-insecure-requests');
  });

  it('開発中だけ、開発サーバーに必要なものを許す', () => {
    const csp = buildContentSecurityPolicy({ ...base, isDev: true });
    expect(csp).toContain('unsafe-eval');
    expect(csp).toContain('ws:');
  });

  it('手元の http では、https への書き換えを付けない', () => {
    const csp = buildContentSecurityPolicy({ ...base, apiUrl: 'http://localhost:3001' });
    expect(csp).not.toContain('upgrade-insecure-requests');
  });

  it('ほかのサイトに埋め込ませない', () => {
    expect(buildContentSecurityPolicy(base)).toContain("frame-ancestors 'none'");
  });
});

describe('buildSecurityHeaders', () => {
  it('手順書の5種類を全部付ける', () => {
    const keys = buildSecurityHeaders(base).map((header) => header.key);
    expect(keys).toEqual(
      expect.arrayContaining([
        'Content-Security-Policy',
        'Strict-Transport-Security',
        'X-Content-Type-Options',
        'Referrer-Policy',
        'Permissions-Policy',
      ]),
    );
  });
});

// 画面の返事に付けるセキュリティのヘッダー（ADR-028・S1-26）。next.config.ts が使う
// ビルドのときに読むので、clientEnv を import しない

type SecurityHeaderInput = {
  apiUrl: string;
  sentryDsn?: string;
  isDev: boolean;
};

export function buildContentSecurityPolicy({ apiUrl, sentryDsn, isDev }: SecurityHeaderInput) {
  // ブラウザの JavaScript が通信してよい相手：自分・API・Sentry の受け口
  // new URL(...).origin は、DSN の鍵（URL のユーザー名の部分）を含まない
  const connectSources = ["'self'", new URL(apiUrl).origin];
  if (sentryDsn) {
    connectSources.push(new URL(sentryDsn).origin);
  }
  if (isDev) {
    connectSources.push('ws:'); // 開発サーバーの自動更新
  }

  const directives = [
    "default-src 'self'",
    // 'unsafe-inline'：公開ページは事前に作って配る（Cache Components）ので、リクエストごとの nonce を
    // 埋め込めない。Next.js の公式の、nonce を使わない設定に従う（弱くなる点は ADR-028）
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ''}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src ${connectSources.join(' ')}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ];
  // HTTPS で動く環境だけ（手元の http://localhost で付けると、CSS や JS の読み込みが https に変わって壊れる）
  if (new URL(apiUrl).protocol === 'https:') {
    directives.push('upgrade-insecure-requests');
  }
  return directives.join('; ');
}

export function buildSecurityHeaders(input: SecurityHeaderInput) {
  return [
    { key: 'Content-Security-Policy', value: buildContentSecurityPolicy(input) },
    // includeSubDomains は付けない（このホストだけに効かせる）
    { key: 'Strict-Transport-Security', value: 'max-age=15552000' },
    { key: 'X-Content-Type-Options', value: 'nosniff' },
    { key: 'X-Frame-Options', value: 'DENY' },
    { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
    { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
  ];
}

import type { BrowserOptions } from '@sentry/nextjs';
import { clientEnv } from './clientEnv';
import { scrubEvent } from './sentryScrub';

// ブラウザ（instrumentation-client.ts）とサーバー（instrumentation.ts）で同じ設定を使う
// DSN がなければ undefined を返す（Sentry を準備しない）
export function sentryOptions(): BrowserOptions | undefined {
  if (!clientEnv.NEXT_PUBLIC_SENTRY_DSN) {
    return undefined;
  }
  return {
    dsn: clientEnv.NEXT_PUBLIC_SENTRY_DSN,
    environment: clientEnv.NEXT_PUBLIC_SENTRY_ENVIRONMENT,
    release: clientEnv.NEXT_PUBLIC_SENTRY_RELEASE,
    // Sentry v11 は、何も書かないと Cookie・ヘッダー・本文・変数の値まで集める。全部集めない（ADR-017）
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
      stackFrameVariables: false,
    },
    // v0.1 はエラーだけ。画面の録画（Session Replay）・トレースは使わない（ADR-017）
    tracesSampleRate: 0,
    beforeSend: scrubEvent,
  };
}

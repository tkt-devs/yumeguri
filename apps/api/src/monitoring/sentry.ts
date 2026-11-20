import type { ErrorEvent, NodeOptions } from '@sentry/node';

// Sentry v11 は、何も書かないと Cookie・ヘッダー・本文・スタックの変数の値まで集める。
// 個人情報や秘密の値が入りうるので、全部集めない（ADR-017）。エラーの種類とスタック（どこで起きたか）は送られる
export const DATA_COLLECTION = {
  userInfo: false,
  cookies: false,
  httpHeaders: false,
  httpBodies: [],
  urlQueryParams: false,
  databaseQueryData: false,
  queues: false,
  stackFrameVariables: false,
} satisfies NodeOptions['dataCollection'];

// Sentry に送る前に、秘密の値が入りうるところを消す（ADR-017）
// 例外のメッセージには、DB の接続の文字列（パスワード入り）などが入ることがある。
// ログと同じく（errors/problem.ts）、エラーの種類とスタック（どこで起きたか）だけを送る
export function scrubEvent(event: ErrorEvent): ErrorEvent {
  for (const exception of event.exception?.values ?? []) {
    exception.value = '[消した]';
  }
  // パンくず（エラーまでの出来事の記録）にも、メッセージが入ることがあるので送らない
  delete event.breadcrumbs;
  return event;
}

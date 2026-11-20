import type { ErrorEvent } from '@sentry/nextjs';

// Sentry に送る前に、秘密の値や個人情報が入りうるところを消す（ADR-017）
// API（apps/api/src/monitoring/sentry.ts）と同じく、エラーの種類とスタック（どこで起きたか）だけを送る
// 環境変数を読まないファイルに分けておく（テストで、環境変数なしに読めるように）
export function scrubEvent(event: ErrorEvent): ErrorEvent {
  for (const exception of event.exception?.values ?? []) {
    exception.value = '[消した]';
  }
  delete event.breadcrumbs;
  return event;
}

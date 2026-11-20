// サーバー（Server Components・Route Handler）で Sentry を準備する（Next.js が起動のときに register を呼ぶ）
import * as Sentry from '@sentry/nextjs';
import { sentryOptions } from './config/sentry';

export function register() {
  const options = sentryOptions();
  if (options) {
    Sentry.init(options);
  }
}

// Server Components・Route Handler で起きたエラーを Sentry に送る（Sentry の公式の手順）
export const onRequestError = Sentry.captureRequestError;

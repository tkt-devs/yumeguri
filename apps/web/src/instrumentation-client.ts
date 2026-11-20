// ブラウザで、画面のコードより先に Sentry を準備する（Next.js がこのファイルを先に読む。Sentry の公式の手順）
import * as Sentry from '@sentry/nextjs';
import { sentryOptions } from './config/sentry';

const options = sentryOptions();
if (options) {
  Sentry.init(options);
}

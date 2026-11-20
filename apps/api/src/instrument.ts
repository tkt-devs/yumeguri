// Sentry（エラーの集め先。ADR-017・S1-20）を、アプリより先に準備する
// node --import ./dist/instrument.js dist/index.js で、index.js より先に読ませる（Sentry の公式の手順）
import * as Sentry from '@sentry/node';
import { loadEnv } from './config/env';
import { DATA_COLLECTION, scrubEvent } from './monitoring/sentry';

const env = loadEnv();

if (env.SENTRY_DSN) {
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.NODE_ENV,
    release: env.SENTRY_RELEASE,
    // 利用者の情報・Cookie・ヘッダー・本文・変数の値などを集めない（ADR-017：個人情報を送らない）
    dataCollection: DATA_COLLECTION,
    // v0.1 はエラーだけ。処理の時間の計測（トレース）は v0.2（ADR-017）
    tracesSampleRate: 0,
    beforeSend: scrubEvent,
  });
}

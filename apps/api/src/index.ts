import { serve } from '@hono/node-server';
import { createApp } from './app';
import { loadEnv } from './config/env';
import { createLogger } from './logger';
import { createPrismaClient, pingDatabase } from './repositories/prismaClient';

// ECS は SIGTERM を送ってから 30 秒で強制的に止める。その前に自分で止まる
const SHUTDOWN_TIMEOUT_MS = 25_000;

const env = loadEnv();
const logger = createLogger(env.LOG_LEVEL);
const prisma = createPrismaClient(env.DATABASE_URL);
const app = createApp({
  logger,
  webOrigin: env.WEB_ORIGIN,
  readinessChecks: [{ name: 'db', check: () => pingDatabase(prisma) }],
});

const server = serve({ fetch: app.fetch, port: env.PORT }, (info) => {
  logger.info({ port: info.port }, 'server started');
});

// 新しいリクエストの受け付けをやめ、処理中のリクエストが終わってから止まる
let shuttingDown = false;
function shutdown(signal: NodeJS.Signals) {
  // 2回目の合図は無視する（once にすると、2回目で Node が即座に終了してしまう）
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info({ signal }, 'shutting down');
  setTimeout(() => {
    logger.error('shutdown timed out');
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS).unref();
  server.close((err) => {
    // 処理中のリクエストが終わってから、DB との接続を閉じる
    void prisma.$disconnect().finally(() => process.exit(err ? 1 : 0));
  });
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

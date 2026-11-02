import { createMiddleware } from 'hono/factory';
import type { Logger } from 'pino';
import type { AppEnv } from '../types';

// リクエストごとに1行の JSON のログを出す。相関 ID の付いたロガーを c.var.logger に入れる
export function requestLogger(logger: Logger) {
  return createMiddleware<AppEnv>(async (c, next) => {
    const startedAt = performance.now();
    c.set('logger', logger.child({ correlationId: c.var.requestId }));
    await next();
    // クエリ（?t=QR のトークン など）は出さないように、path だけを出す
    c.var.logger.info(
      {
        method: c.req.method,
        path: c.req.path,
        status: c.res.status,
        durationMs: Math.round(performance.now() - startedAt),
      },
      'request',
    );
  });
}

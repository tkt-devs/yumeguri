import { Hono } from 'hono';
import { requestId } from 'hono/request-id';
import { handleError, handleNotFound } from './errors/problem';
import { requestLogger } from './middleware/logger';
import { createRoutes } from './routes';
import type { AppDeps, AppEnv } from './types';

export const CORRELATION_ID_HEADER = 'X-Correlation-Id';

// ミドルウェアの順番は変えない（相関 ID → ログ。逆にすると、ログに相関 ID が付かない）
export function createApp(deps: AppDeps) {
  return new Hono<AppEnv>()
    .use(requestId({ headerName: CORRELATION_ID_HEADER }))
    .use(requestLogger(deps.logger))
    .route('/', createRoutes(deps))
    .notFound(handleNotFound)
    .onError(handleError);
}

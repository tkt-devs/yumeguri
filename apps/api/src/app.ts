import { CORRELATION_ID_HEADER } from '@yumeguri/shared';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { requestId } from 'hono/request-id';
import { handleError, handleNotFound } from './errors/problem';
import { requestLogger } from './middleware/logger';
import { createRoutes } from './routes';
import type { AppDeps, AppEnv } from './types';

// ミドルウェアの順番は変えない（相関 ID → ログ。逆にすると、ログに相関 ID が付かない）
export function createApp(deps: AppDeps) {
  return (
    new Hono<AppEnv>()
      .use(requestId({ headerName: CORRELATION_ID_HEADER }))
      .use(requestLogger(deps.logger))
      // 画面（WEB_ORIGIN）からだけ、ブラウザで API を呼べるようにする。Cookie を送らせるので credentials も許す
      // 相関 ID のヘッダーは、許可しないとブラウザの JavaScript から読めない
      .use(
        cors({
          origin: deps.webOrigin,
          credentials: true,
          exposeHeaders: [CORRELATION_ID_HEADER],
        }),
      )
      .route('/', createRoutes(deps))
      .notFound(handleNotFound)
      .onError(handleError)
  );
}

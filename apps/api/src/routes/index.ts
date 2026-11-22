import { Hono } from 'hono';
import type { AppDeps, AppEnv } from '../types';
import { createHealthRoutes } from './health';
import { createStoreRoutes } from './stores';

// ここを見れば、全部のエンドポイントが分かる
export function createRoutes(deps: AppDeps) {
  const v1 = new Hono<AppEnv>().route('/stores', createStoreRoutes(deps.storeService));

  return new Hono<AppEnv>()
    .route('/', createHealthRoutes(deps.readinessChecks)) // /healthz・/readyz
    .route('/v1', v1);
}

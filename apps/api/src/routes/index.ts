import { Hono } from 'hono';
import type { AppDeps, AppEnv } from '../types';
import { createHealthRoutes } from './health';

// ここを見れば、全部のエンドポイントが分かる
export function createRoutes(deps: AppDeps) {
  return new Hono<AppEnv>().route('/', createHealthRoutes(deps.readinessChecks)); // /healthz・/readyz
}

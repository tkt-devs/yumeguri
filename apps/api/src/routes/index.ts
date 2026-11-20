import { Hono } from 'hono';
import type { AppDeps, AppEnv } from '../types';
import { createHealthRoutes } from './health';

// ここを見れば、全部のエンドポイントが分かる
export function createRoutes(deps: AppDeps) {
  return (
    new Hono<AppEnv>()
      .route('/', createHealthRoutes(deps.readinessChecks)) // /healthz・/readyz
      // S1-20 の確認用：わざとエラーを起こして、Sentry に届くかを見る。確かめたら消す
      .get('/debug/sentry-error', () => {
        throw new Error('S1-20 の確認用のエラー');
      })
  );
}

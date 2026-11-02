import type { RequestIdVariables } from 'hono/request-id';
import type { Logger } from 'pino';
import type { ReadinessCheck } from './services/readiness';

// Hono の c.var で使える値（相関 ID と、相関 ID の付いたロガー）
export type AppEnv = {
  Variables: RequestIdVariables & { logger: Logger };
};

// アプリの組み立てに外から渡すもの（テストでは偽物に差し替える）
export type AppDeps = {
  logger: Logger;
  readinessChecks: readonly ReadinessCheck[];
};

import { Hono } from 'hono';
import { assertReady, type ReadinessCheck } from '../services/readiness';
import type { AppEnv } from '../types';

export function createHealthRoutes(checks: readonly ReadinessCheck[]) {
  return (
    new Hono<AppEnv>()
      // ALB のヘルスチェック用。プロセスが生きていれば、いつも 200（DB などは見ない）
      .get('/healthz', (c) => c.json({ status: 'ok' }, 200))
      // DB などにつながるか。1つでもだめなら 503
      .get('/readyz', async (c) => {
        await assertReady(checks, c.var.logger);
        return c.json({ status: 'ok' }, 200);
      })
  );
}

import type { Logger } from 'pino';
import { ServiceUnavailableError } from '../errors/appError';

// 1つの相手を確かめるのに待つ上限。返ってこない相手がいても、/readyz は止まらずに 503 を返す
export const READINESS_CHECK_TIMEOUT_MS = 2_000;

// /readyz で確かめる相手（DB・Valkey・SQS）。つながらなければ check が例外を投げる
export type ReadinessCheck = {
  name: string;
  check: () => Promise<void>;
};

// check が時間内に終わらなければ失敗にする（check がその場で例外を投げても、失敗として扱う）
function checkInTime(target: ReadinessCheck): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), READINESS_CHECK_TIMEOUT_MS);
    target
      .check()
      .then(resolve, reject)
      .finally(() => clearTimeout(timer));
  });
}

// 全部を同時に確かめる。1つでもつながらなければ、どれがだめかをログに出して 503 にする
export async function assertReady(
  checks: readonly ReadinessCheck[],
  logger: Logger,
): Promise<void> {
  const results = await Promise.all(
    checks.map((target) =>
      checkInTime(target).then(
        () => null,
        () => target.name,
      ),
    ),
  );
  const failed = results.filter((name) => name !== null);
  if (failed.length > 0) {
    logger.warn({ failed }, 'not ready');
    throw new ServiceUnavailableError();
  }
}

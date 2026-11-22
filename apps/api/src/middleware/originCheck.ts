import type { MiddlewareHandler } from 'hono';
import { ForbiddenError } from '../errors/appError';
import type { AppEnv } from '../types';

// データを変えないメソッド。これ以外（POST・PUT・PATCH・DELETE）は Origin を確かめる
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

// CSRF の対策（ADR-003・S1-26）。ほかのサイトのフォームから送られた POST は、CORS では止まらず、
// API の処理まで届く。ブラウザが付ける Origin ヘッダーが、画面のオリジンとちょうど同じときだけ通す
// Origin がないリクエストも断る（確かめられないものは通さない）
export function originCheck(allowedOrigin: string): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    if (!SAFE_METHODS.has(c.req.method) && c.req.header('Origin') !== allowedOrigin) {
      throw new ForbiddenError();
    }
    await next();
  };
}

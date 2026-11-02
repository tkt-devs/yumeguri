import { ERROR_STATUS, type ProblemDetails } from '@yumeguri/shared';
import type { Context, ErrorHandler, NotFoundHandler } from 'hono';
import type { AppEnv } from '../types';
import { AppError, InternalError, NotFoundError } from './appError';

const PROBLEM_TYPE_BASE = 'https://api.sento-stamprally.com/problems/';

// AppError を RFC 9457 の形（application/problem+json）で返す
function problem(c: Context<AppEnv>, err: AppError) {
  const status = ERROR_STATUS[err.code];
  const body: ProblemDetails = {
    type: PROBLEM_TYPE_BASE + err.code.toLowerCase().replaceAll('_', '-'),
    title: err.message,
    status,
    code: err.code,
    correlationId: c.var.requestId,
  };
  return c.json(body, status, { 'Content-Type': 'application/problem+json' });
}

export const handleNotFound: NotFoundHandler<AppEnv> = (c) => problem(c, new NotFoundError());

export const handleError: ErrorHandler<AppEnv> = (err, c) => {
  if (err instanceof AppError) {
    return problem(c, err);
  }
  // 予期しないエラー。例外のメッセージには秘密の値が入ることがあるので、
  // レスポンスにもログにも出さない。ログには種類と、どこで起きたか（スタックの「at …」の部分）だけ出す
  // スタックの先頭には「名前: メッセージ」がそのまま入っている（複数行のこともある）ので、
  // その部分をまるごと切り落とす。形が違って切り落とせないときは、スタックごと出さない
  const header = String(err);
  const where = err.stack?.startsWith(header) ? err.stack.slice(header.length).trim() : undefined;
  c.var.logger.error({ errorName: err.name, stack: where }, 'unexpected error');
  return problem(c, new InternalError());
};

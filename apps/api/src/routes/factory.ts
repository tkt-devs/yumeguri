import { createFactory } from 'hono/factory';
import type { AppEnv } from '../types';

// バリデーターとハンドラーを一緒に作ると、別のファイルでも c.req.valid() の型が付く
export const factory = createFactory<AppEnv>();

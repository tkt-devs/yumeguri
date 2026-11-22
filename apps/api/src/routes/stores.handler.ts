import { cursorPageQuerySchema } from '@yumeguri/shared';
import { z } from 'zod';
import { validate } from '../middleware/validate';
import type { StoreService } from '../services/storeService';
import { factory } from './factory';

const StoreSlugParam = z.object({ slug: z.string() });

// ハンドラーは「受け取る → Service を呼ぶ → 返す」だけ
export function createStoreHandlers(storeService: StoreService) {
  return {
    listStoresHandlers: factory.createHandlers(
      validate('query', cursorPageQuerySchema),
      async (c) => {
        const page = await storeService.listPublic(c.req.valid('query'));
        return c.json(page, 200);
      },
    ),
    getStoreHandlers: factory.createHandlers(validate('param', StoreSlugParam), async (c) => {
      const { slug } = c.req.valid('param');
      const store = await storeService.getPublicBySlug(slug);
      return c.json(store, 200);
    }),
  };
}

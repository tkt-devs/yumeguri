import { Hono } from 'hono';
import type { StoreService } from '../services/storeService';
import type { AppEnv } from '../types';
import { createStoreHandlers } from './stores.handler';

// 公開の銭湯（だれでも見られる）
export function createStoreRoutes(storeService: StoreService) {
  const { listStoresHandlers, getStoreHandlers } = createStoreHandlers(storeService);
  return new Hono<AppEnv>().get('/', ...listStoresHandlers).get('/:slug', ...getStoreHandlers);
}

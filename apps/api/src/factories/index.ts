import type { Env } from '../config/env';
import type { PrismaClient } from '../generated/prisma/client';
import { PrismaStoreRepository } from '../repositories/storeRepository';
import { StoreService } from '../services/storeService';

// 起動のときに1回だけ、Repository を作って Service に渡す
export function createServices(prisma: PrismaClient, env: Pick<Env, 'PUBLIC_IMAGE_BASE_URL'>) {
  const storeRepository = new PrismaStoreRepository(prisma);
  return {
    storeService: new StoreService(storeRepository, env.PUBLIC_IMAGE_BASE_URL),
  };
}

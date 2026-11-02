import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';

// DB につながるまで待つ上限。DB が返事をしないときに、接続の試みがたまり続けないようにする
const CONNECTION_TIMEOUT_MS = 2_000;

// Prisma Client を作る。DB への接続は pg（node-postgres）が受け持つ（Prisma 7 の driver adapter）
export function createPrismaClient(connectionString: string): PrismaClient {
  return new PrismaClient({
    adapter: new PrismaPg({ connectionString, connectionTimeoutMillis: CONNECTION_TIMEOUT_MS }),
  });
}

// DB に問い合わせができるかを確かめる（/readyz で使う）
export async function pingDatabase(prisma: PrismaClient): Promise<void> {
  await prisma.$queryRaw`SELECT 1`;
}

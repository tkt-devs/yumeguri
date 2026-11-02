import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // 公開ページのキャッシュは 'use cache' で書く（S0-11 で Vercel で確かめた書き方）
  cacheComponents: true,
  partialPrefetching: true,
  // @yumeguri/shared は .ts のまま渡しているので、Next.js に変換してもらう
  transpilePackages: ['@yumeguri/shared'],
};

export default nextConfig;

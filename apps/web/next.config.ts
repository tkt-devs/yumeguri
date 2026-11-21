import type { NextConfig } from 'next';
import { buildSecurityHeaders } from './src/config/securityHeaders';

const nextConfig: NextConfig = {
  // 公開ページのキャッシュは 'use cache' で書く（S0-11 で Vercel で確かめた書き方）
  cacheComponents: true,
  partialPrefetching: true,
  // @yumeguri/shared は .ts のまま渡しているので、Next.js に変換してもらう
  transpilePackages: ['@yumeguri/shared'],
  // Sentry のリリース（どのコードのエラーか）。Vercel がビルドのときに入れるコミット ID の先頭 12 文字
  // （API・ワーカーのイメージのタグと同じ形。ADR-017・S1-20）
  env: {
    NEXT_PUBLIC_SENTRY_RELEASE: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 12) ?? 'dev',
  },
  // 全部の画面に、セキュリティのヘッダーを付ける（ADR-028・S1-26）
  async headers() {
    const apiUrl = process.env.NEXT_PUBLIC_API_URL;
    if (!apiUrl) {
      throw new Error('NEXT_PUBLIC_API_URL がない');
    }
    return [
      {
        source: '/:path*',
        headers: buildSecurityHeaders({
          apiUrl,
          sentryDsn: process.env.NEXT_PUBLIC_SENTRY_DSN || undefined,
          isDev: process.env.NODE_ENV === 'development',
        }),
      },
    ];
  },
};

export default nextConfig;

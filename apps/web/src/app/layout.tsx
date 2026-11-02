import type { Metadata } from 'next';
import { QueryProvider } from '@/providers/QueryProvider';
import '@/styles/globals.css';

export const metadata: Metadata = {
  title: 'ゆめぐり',
  description: '銭湯めぐりのスタンプラリー（学習用）',
};

// 全部の画面の外枠
export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ja">
      <body>
        <QueryProvider>{children}</QueryProvider>
      </body>
    </html>
  );
}

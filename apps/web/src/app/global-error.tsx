'use client';

import * as Sentry from '@sentry/nextjs';
import { useEffect } from 'react';

// いちばん外側（layout.tsx）でエラーが起きたときの画面。error.tsx では受け止められないので、
// html・body から自分で書く（Next.js の決まり）。Sentry には送る（Sentry の公式の手順）
export default function GlobalError({ error }: { error: Error & { digest?: string } }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="ja">
      <body>
        <main>
          <h1>エラーが起きました</h1>
          <p>時間をおいて、もう一度お試しください。</p>
        </main>
      </body>
    </html>
  );
}

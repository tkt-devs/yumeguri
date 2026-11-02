'use client';

import styles from './status.module.css';

// 画面を表示する途中で、予期しないエラーが起きたときの画面（500）
// エラーの中身は画面に出さない（秘密の値や内部の情報が入っていることがあるため）
export default function ErrorPage({ retry }: { error: unknown; retry: () => void }) {
  return (
    <main className={styles.page}>
      <h1>エラーが起きました</h1>
      <p>時間をおいて、もう一度お試しください。</p>
      <button type="button" className={styles.button} onClick={retry}>
        もう一度読み込む
      </button>
    </main>
  );
}

import Link from 'next/link';
import styles from './status.module.css';

// 存在しない URL のときの画面（404）
export default function NotFound() {
  return (
    <main className={styles.page}>
      <h1>ページが見つかりません</h1>
      <p>URL が間違っているか、ページがなくなった可能性があります。</p>
      <Link href="/">トップへ戻る</Link>
    </main>
  );
}

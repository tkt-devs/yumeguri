import styles from './status.module.css';

// 画面のデータを読み込んでいる間の表示
export default function Loading() {
  return (
    <main className={styles.page}>
      <p role="status">読み込み中…</p>
    </main>
  );
}

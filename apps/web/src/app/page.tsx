import { ApiStatusContainer } from '@/components/container/ApiStatusContainer';
import styles from './page.module.css';

// トップページ。いまは、画面から API と DB までつながるかの確認だけ（S1-18 の確認用。あとで消す）
export default function HomePage() {
  return (
    <main className={styles.page}>
      <h1>ゆめぐり</h1>
      <ApiStatusContainer />
    </main>
  );
}

import { useId } from 'react';
import styles from './ApiStatus.module.css';

type Props =
  | { state: 'checking' }
  | { state: 'ok' }
  | { state: 'down'; correlationId: string | null; onRetry: () => void };

// API の状態を表示する（S1-18 の確認用。あとで消す）
export function ApiStatus(props: Props) {
  const titleId = useId();
  return (
    <section className={styles.card} aria-labelledby={titleId}>
      <h2 id={titleId}>API の状態</h2>
      {props.state === 'checking' && <p role="status">確かめています…</p>}
      {props.state === 'ok' && (
        <p role="status" className={styles.ok}>
          つながっています（API・DB）
        </p>
      )}
      {props.state === 'down' && (
        <>
          <p role="alert" className={styles.down}>
            つながりません
          </p>
          {props.correlationId && <p className={styles.note}>相関 ID：{props.correlationId}</p>}
          <button type="button" className={styles.button} onClick={props.onRetry}>
            もう一度確かめる
          </button>
        </>
      )}
    </section>
  );
}

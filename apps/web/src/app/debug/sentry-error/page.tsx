'use client';

// S1-20 の確認用：ボタンを押すとブラウザでわざとエラーを起こし、Sentry に届くかを見る。確かめたら消す
export default function SentryErrorPage() {
  return (
    <main>
      <h1>Sentry の確認</h1>
      <button
        type="button"
        onClick={() => {
          throw new Error('S1-20 の確認用のエラー（ブラウザ）');
        }}
      >
        エラーを起こす
      </button>
    </main>
  );
}

# ADR-028: セキュリティヘッダーはアプリで付け、CSP は nonce を使わない形にする

- 状態：決定
- 日付：2026-11-21

## 背景

Web（Vercel）と API（ECS）に、CSP・HSTS・X-Content-Type-Options・Referrer-Policy・Permissions-Policy を付ける（S1-26）。付ける場所を、アプリか Cloudflare のレスポンスヘッダーのルールかから決める。また、Web の公開ページは事前に作って配る（Cache Components）ので、CSP の書き方も決める必要がある。

## 選択肢

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| アプリで付ける（Hono・`next.config.ts`） | コードと一緒にレビューとテストができる。手元でも同じヘッダーで動く。Cloudflare を替えても残る | Web と API の2か所に書く |
| Cloudflare のルールで付ける | 1か所で済む | テストができない。手元では付かない。画面ごとの API や Sentry の宛先を、アプリと別の場所で管理する |
| CSP に nonce を使う | インラインのスクリプトを厳しく絞れる | 全部の画面が動的な描画になり、Cache Components の事前の描画が使えない（Next.js の公式の説明） |
| CSP に nonce を使わない | 公開ページを事前に作って配れる | `script-src` に `'unsafe-inline'` が要る |

## 決めたこと

- **ヘッダーはアプリで付ける。** API は `apps/api/src/middleware/securityHeaders.ts`、Web は `apps/web/src/config/securityHeaders.ts`（`next.config.ts` から使う）
- **Web の CSP は nonce を使わない。** 通信先（`connect-src`）は、自分・API・Sentry の受け口だけにする
- API は JSON しか返さないので、CSP は `default-src 'none'` にする
- HSTS は `max-age=15552000`（180日）。`includeSubDomains` と `preload` は付けない

## 理由

- セキュリティの設定は、変更の履歴・レビュー・テストが残る場所に置きたい
- 公開ページの速さは、この製品の要件（Cache Components を選んだ理由）なので、nonce のために捨てない

## 捨てた選択肢

- **Cloudflare のルール**：テストができず、手元と staging で動きが変わるので採らない
- **nonce**：公開ページの事前の描画が使えなくなるので採らない
- **SRI（ハッシュ）**：Next.js で実験的な機能なので、v0.1 では採らない

## リスクと、その対策

- `'unsafe-inline'` があるので、**CSP だけでは、ページに入り込んだインラインのスクリプトを止められない**。React の自動エスケープに頼り、`dangerouslySetInnerHTML` を使わない。ログインは HttpOnly の Cookie なので、スクリプトから値を読まれない。通信先を絞っているので、外へのデータの持ち出しも難しくする
- 新しい外部サービス（画像の配信元など）を使うときは、CSP に足さないとブラウザが止める。画像の配信元は、写真を表示するステップで `img-src` に足す
- Vercel の Preview では、Vercel のツールバーのスクリプトが CSP で止まることがある。アプリの動きには関係しない
- Origin の確認は、Origin がないリクエストも断る。将来、ブラウザ以外から POST を受ける場所（Webhook など）を作るときは、別の認証を付けて、この確認の対象から外す

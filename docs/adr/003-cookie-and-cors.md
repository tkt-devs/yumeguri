# ADR-003: Web と API を別のサブドメインにしたときの Cookie と CORS

- 状態：決定
- 日付：2026-10-30

## 背景

Web は Vercel の `app.`、API は AWS の `api.` にある（ADR-001）。ブラウザから見ると、2つは別のオリジンなので、ログインの Cookie と、別のオリジンへのリクエストの許可（CORS）を決める必要がある。

## 選択肢

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| 別のサブドメイン（`app.` と `api.`） | Web と API を、それぞれの得意な場所（Vercel と AWS）に置ける | CORS の設定が要る。JSON の POST の前に、ブラウザが確認のリクエスト（OPTIONS）を送るので、1往復増える |
| 同じドメインの下のパスに分ける（`app.…/api/*` を API に転送する） | CORS が要らない | Vercel から AWS へ、もう1段の転送が入る。転送の設定と、そこでの障害を自分で管理する必要がある |

## 決めたこと

**`app.` と `api.` を別のサブドメインのまま使う。** 次のように設定する。

- ログインの Cookie は、**API（`api.`）が発行し、`api.` のホストだけに付く**ようにする（`Domain` の属性を付けない）。属性は `HttpOnly`・`Secure`・`SameSite=Lax`・`Path=/`
- `app.` と `api.` は同じサイト（`sento-stamprally.com`）なので、`SameSite=Lax` の Cookie も、画面からの `fetch` に付いて送られる
- 画面は `fetch` に `credentials: 'include'` を付ける
- API の CORS は、`Access-Control-Allow-Origin` に `https://app.…`（ちょうどこの値だけ）を返し、`Access-Control-Allow-Credentials: true` を返す。確認のリクエストの結果は `Access-Control-Max-Age` で、しばらく覚えさせる
- 状態を変えるリクエスト（POST・PATCH・DELETE）では、`Origin` ヘッダーが `app.` かを確かめる（CSRF の対策）

## 理由

- Web と API を、それぞれ一番動かしやすい場所に置ける（ADR-001・002）
- Cookie を `api.` のホストだけに付けるので、Vercel 側には、ログインの Cookie が一度も送られない
- CORS・CSRF・Cookie の属性は、カリキュラム（Day 74・78）で学ぶ内容そのものなので、自分で設定する価値がある

## 捨てた選択肢

- **同じドメインのパスに分ける**：転送の段が1つ増え、その障害の調べ方まで学ぶことになるので採らない

## リスクと、その対策

- 確認のリクエスト（OPTIONS）の分だけ遅くなる。`Access-Control-Max-Age` で回数を減らす
- Next.js のサーバー側（Server Component）からは、`api.` の Cookie を読めない。ログインが必要な画面は、ブラウザ側（Client Component）で API を呼ぶ形にする（`apps/web/AGENTS.md`）
- CORS の許可を `*` にすると、Cookie を送れなくなるうえ、危険でもある。許可するオリジンは、環境変数で1つだけ指定する

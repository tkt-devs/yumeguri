# API v0.1

開発手順書の S0-14。v0.1 で作るエンドポイントだけを書く。S1-05 で、この表を見ながら Zod のスキーマを書く。

## 共通のルール

| 項目 | 決めたこと |
| --- | --- |
| 住所 | `https://api.sento-stamprally.com/v1/...`（ローカルは `http://localhost:3001/v1/...`） |
| 形式 | JSON（UTF-8） |
| 項目の名前 | **camelCase**（例：`displayName`）。DB の列は snake_case なので、Prisma の `@map` で変換する |
| 日時 | ISO 8601 の UTC（例：`2026-11-14T12:00:00Z`）。画面で JST にして表示する |
| 日付 | `YYYY-MM-DD`（例：`visitedOn: "2026-11-14"`）。来訪の日付は **JST の日付** |
| 時刻 | `HH:MM`（例：営業時間 `opensAt: "15:00"`） |
| ID | UUID v7 の文字列 |
| ログイン | Cookie（`sid`、HttpOnly・Secure・SameSite=Lax）。画面（`app.`）から API（`api.`）を呼ぶときは `credentials: "include"` を付ける |
| CORS | `https://app.sento-stamprally.com` だけを許可し、`Access-Control-Allow-Credentials: true` を返す（Cookie を送らせるため。`*` は使えない） |
| CSRF | 状態を変えるリクエスト（POST・PATCH・DELETE）では、`Origin` ヘッダーが `app.` かを確かめる |
| 相関 ID | `X-Correlation-Id` を受け取るか作り、レスポンスのヘッダーと、エラーの本文に入れる |

## エラーの形（RFC 9457）

エラーのときは、`Content-Type: application/problem+json` で、いつも同じ形で返す。

```json
{
  "type": "https://api.sento-stamprally.com/problems/validation-failed",
  "title": "入力に誤りがあります",
  "status": 422,
  "code": "VALIDATION_FAILED",
  "correlationId": "01JC8Z...",
  "errors": [
    { "path": "businessHours.0.opensAt", "message": "HH:MM の形で入力してください" }
  ]
}
```

- `code` を見て、画面が表示を変える（`title` の文章で判定しない。文章は変わることがある）
- `errors` は、入力のエラー（`VALIDATION_FAILED`）のときだけ
- **スタックトレース・SQL・内部の詳細は返さない**（ログにだけ出す。相関 ID でログとつなげる）

## エラーコードの一覧

| code | HTTP | いつ | 画面での表示（例） |
| --- | --- | --- | --- |
| `AUTH_REQUIRED` | 401 | ログインしていない。セッションが期限切れ・ログアウト済み | ログイン画面へ移る |
| `FORBIDDEN` | 403 | ログインしているが、その操作の権限がない（例：スタッフが銭湯の情報を編集しようとした）。停止中の利用者 | 「この操作はできません」 |
| `NOT_FOUND` | 404 | ない。**または、他の団体のデータ**（存在するかどうかを教えないため、403 にしない。要件定義書 8.1） | 「見つかりません」 |
| `VALIDATION_FAILED` | 422 | 入力が Zod の検証に通らない（形が違う・足りない・範囲の外） | 項目のそばにエラーを出す |
| `TOKEN_INVALID` | 400 | QR のトークンが壊れている・署名が合わない | 「この QR は使えません。お店の QR を読み直してください」 |
| `TOKEN_EXPIRED` | 400 | QR のトークンの期限（60秒）が切れている | 「QR の期限が切れました。もう一度読んでください」 |
| `TOKEN_ALREADY_USED` | 409 | QR を、**別の人が** すでに使った | 「QR を読み直してください」 |
| `INTERNAL_ERROR` | 500 | 予期しないエラー | 「時間をおいて試してください」＋相関 ID |
| `SERVICE_UNAVAILABLE` | 503 | DB などにつながらない（`/readyz`） | （ALB・監視用） |

- **`ALREADY_CHECKED_IN` はエラーにしない**。同じ日の2回目のチェックインは、**200** で、本文の `result: "already_checked_in"` で知らせる（要件定義書 9.4。利用者は何も悪いことをしていないので、エラーの画面を出さない）
- 回数の上限（`RATE_LIMITED`・429）は、v0.2 の S1-25 で足す（v0.1 は Cloudflare のレート制限のルールだけ）

## 一覧の形（カーソル方式のページ送り）

```
GET /v1/stores?limit=20&cursor=eyJu...
```

```json
{
  "items": [ ... ],
  "nextCursor": "eyJuIjoi5qKF44Gu5rmvIiwiaSI6IjAxOTMuLi4ifQ"
}
```

- `limit`：初期値 20、上限 50
- `nextCursor`：次のページがなければ `null`
- カーソルの中身は「**最後の行の並べ替えの値 ＋ id**」（例：`{"n":"梅の湯","i":"0193..."}`）を base64url にしたもの。名前が同じ銭湯があっても、重複や抜けが出ないように id も入れる。画面は中身を気にせず、そのまま次のリクエストに付ける
- ページ番号の方式（`?page=3`）にしない理由：途中で行が増えると、ずれて重複する。行が多いと、後ろのページほど遅くなる

## エンドポイント

### 1. ログイン（Google）

|                                                         |     |
| ------------------------------------------------------- | --- |
| **GET** `/v1/auth/google/start?returnTo=/checkin?t=...` | 誰でも |

- `returnTo`：ログインのあとに戻る画面。**`/` から始まるパスだけ** 受け付ける（`https://evil.example` のような外の URL は無視して `/` にする。オープンリダイレクトの対策）
- 成功：**302** で Google の画面へ（`state`・`nonce`・PKCE の値を、短い期限の Cookie に入れる）

| | |
| --- | --- |
| **GET** `/v1/auth/google/callback?code=...&state=...` | 誰でも（Google から戻ってくる） |

- 成功：セッションを作り、`sid` の Cookie を付けて、**302** で `https://app.../{returnTo}` へ
- 失敗（`state` の不一致・ID トークンの検証の失敗など）：**302** で `https://app.../login?error=login_failed` へ（ブラウザが直接開くページなので、JSON のエラーは返さない）

### 2. ログアウト

| | |
| --- | --- |
| **POST** `/v1/auth/logout` | ログイン |
| **POST** `/v1/auth/logout-all` | ログイン |

- 成功：**204**（本文なし）。`logout` は今のセッション、`logout-all` は自分のすべてのセッションに `revoked_at` を入れ、Cookie を消す
- エラー：`AUTH_REQUIRED`

### 3. 自分の情報

| | |
| --- | --- |
| **GET** `/v1/me` | ログイン |

```json
{
  "id": "0193...",
  "displayName": "Shota",
  "email": "shota@example.com",
  "memberships": [
    {
      "organizationId": "0193...",
      "organizationName": "A 浴場組合",
      "storeId": "0193...",
      "storeName": "梅の湯",
      "role": "owner"
    }
  ],
  "platformRoles": []
}
```

- `memberships[].storeId`・`storeName`：団体の管理者（`org_admin`）は `null`
- 画面は、これを見て「スタッフのメニュー」などを出し分ける（**出し分けは見た目だけ**。本当の権限の判定は、毎回 API が行う）
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`（停止中の利用者）

### 4. 銭湯の一覧（公開）

| | |
| --- | --- |
| **GET** `/v1/stores?limit=&cursor=` | 誰でも |

```json
{
  "items": [
    {
      "id": "0193...",
      "slug": "ume-no-yu",
      "name": "梅の湯",
      "thumbnailUrl": "https://img.sento-stamprally.com/stores/0193.../a1b2c3.webp"
    }
  ],
  "nextCursor": null
}
```

- 出すのは `status = published` で、消されていない銭湯だけ。名前の順
- `thumbnailUrl`：並び順が一番前の、準備完了の写真。なければ `null`
- エラー：`VALIDATION_FAILED`（`limit` が範囲の外、`cursor` が壊れている）

### 5. 銭湯の詳細（公開）

| | |
| --- | --- |
| **GET** `/v1/stores/{slug}` | 誰でも |

公開ページの URL（`/stores/ume-no-yu`）と合わせて、**slug で探す**（id ではない）。

```json
{
  "id": "0193...",
  "slug": "ume-no-yu",
  "name": "梅の湯",
  "nameKana": "うめのゆ",
  "description": "...",
  "prices": { "adult": 600, "child": 200 },
  "status": "published",
  "businessHours": [
    { "weekday": 1, "opensAt": "15:00", "closesAt": "01:00" }
  ],
  "photos": [
    { "id": "0193...", "url": "https://img.sento-stamprally.com/...", "width": 1200, "height": 800 }
  ]
}
```

- `status`：`published` か `closed`（閉業していても、ページは「閉業しました」と出すために返す）
- `businessHours`：曜日・開店の順。`closesAt < opensAt` なら日付をまたぐ（画面で「翌1:00」と出す）。行がない曜日は定休日
- `photos`：準備完了の写真だけ、並び順で
- エラー：`NOT_FOUND`（ない・下書き・消されている）

### 6. 銭湯の詳細（オーナー用）

| | |
| --- | --- |
| **GET** `/v1/owner/stores/{id}` | オーナー以上（自分の銭湯） |

- 本文は 5 と同じ形。ただし **下書き（`draft`）も見られる**。写真は、加工中・失敗のものも `status` 付きで返す（編集の画面で「加工中」と出すため）
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`（自分の団体の銭湯だが、スタッフの役割しかない）、`NOT_FOUND`（他の団体の銭湯）

### 7. 銭湯の情報を編集する

| | |
| --- | --- |
| **PATCH** `/v1/owner/stores/{id}` | オーナー以上（自分の銭湯） |

```json
{
  "name": "梅の湯",
  "nameKana": "うめのゆ",
  "description": "...",
  "prices": { "adult": 600, "child": 200 },
  "businessHours": [
    { "weekday": 1, "opensAt": "15:00", "closesAt": "01:00" }
  ]
}
```

- 送った項目だけを変える（PATCH）。ただし `businessHours` は、**送った内容で全部を置き換える**（1行ずつの追加・削除の API を作らない）
- 検証：`name` は1〜50文字、`weekday` は 0〜6、時刻は `HH:MM`、`opensAt` と `closesAt` は同じにしない、`prices` の金額は 0 以上の整数
- `status`（公開・閉業）は、ここでは変えない（団体の管理者の操作。v0.1 では作らない）
- 成功：**200**、本文は 6 と同じ形（保存したあとの内容）。保存したら、公開ページの作り直し（Vercel の `/api/revalidate`）を呼ぶ
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`、`NOT_FOUND`、`VALIDATION_FAILED`

### 8. 写真のアップロード用の URL をもらう

| | |
| --- | --- |
| **POST** `/v1/owner/stores/{id}/photos/upload-url` | オーナー以上（自分の銭湯） |

```json
{ "contentType": "image/jpeg", "size": 2480000 }
```

- `contentType`：`image/jpeg`・`image/png`・`image/webp` のどれか。`size`：10MB まで
- Photo を `uploading` で作り、S3 の **署名つきの POST** を発行する（10分、このファイル1つだけ、大きさの上限つき）
- 成功：**201**

```json
{
  "photoId": "0193...",
  "upload": {
    "url": "https://....s3.ap-northeast-1.amazonaws.com/",
    "fields": { "key": "uploads/0193.../original", "Policy": "...", "X-Amz-Signature": "..." }
  },
  "expiresAt": "2026-11-14T12:10:00Z"
}
```

- 画面は `upload.url` に、`fields` とファイルを **multipart/form-data で直接送る**（API を通さない）
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`、`NOT_FOUND`、`VALIDATION_FAILED`

### 9. アップロードが終わったことを知らせる

| | |
| --- | --- |
| **POST** `/v1/owner/stores/{id}/photos/{photoId}/complete` | オーナー以上（自分の銭湯） |

- 本文なし
- Photo を `processing` にし、加工のジョブ（`photo.process`）を作って SQS に送る
- 成功：**202**（加工は待たない）

```json
{ "jobId": "0193..." }
```

- 同じ写真で2回呼ばれても、ジョブは1つだけ（Job の `idempotency_key = photo.process:<photoId>`）。2回目も同じ `jobId` を返す
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`、`NOT_FOUND`、`VALIDATION_FAILED`（S3 にファイルがまだない）

### 10. ジョブの状態

| | |
| --- | --- |
| **GET** `/v1/jobs/{id}` | ジョブを作った人・システムの管理者 |

```json
{
  "id": "0193...",
  "type": "photo.process",
  "status": "running",
  "progress": 40,
  "error": null,
  "createdAt": "2026-11-14T12:00:00Z",
  "finishedAt": null
}
```

- 画面は、`succeeded`・`failed`・`dead`・`cancelled` になるまで、2秒ごとに取りに行く（ポーリング）
- `error`：失敗したときの、利用者に見せてよい短い説明（内部のエラーの詳細は出さない）
- エラー：`AUTH_REQUIRED`、`NOT_FOUND`（ない・他の人のジョブ）

### 11. QR のトークンを発行する（スタッフ端末）

| | |
| --- | --- |
| **POST** `/v1/staff/stores/{id}/checkin-tokens` | スタッフ以上（自分の銭湯） |

- 本文なし。タブレットが30秒ごとに呼ぶ
- 成功：**201**

```json
{
  "token": "eyJ...",
  "checkinUrl": "https://app.sento-stamprally.com/checkin?t=eyJ...",
  "expiresAt": "2026-11-14T12:01:00Z"
}
```

- タブレットは `checkinUrl` を QR にして表示する
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`、`NOT_FOUND`（他の団体の銭湯・公開していない銭湯）

### 12. チェックイン

| | |
| --- | --- |
| **POST** `/v1/checkins` | ログイン（来訪者） |

```json
{ "token": "eyJ..." }
```

- 同期で返す（利用者はその場で結果を見たいので。すぐ終わる処理）
- 成功（初めて）：**201**

```json
{
  "result": "checked_in",
  "visit": { "id": "0193...", "storeId": "0193...", "storeName": "梅の湯", "visitedOn": "2026-11-14" }
}
```

- 成功（同じ日の2回目）：**200**。形は同じで、`result: "already_checked_in"`、`visit` は最初の来訪
- エラー：`AUTH_REQUIRED`、`FORBIDDEN`（停止中の利用者）、`TOKEN_INVALID`、`TOKEN_EXPIRED`、`TOKEN_ALREADY_USED`、`NOT_FOUND`（公開していない銭湯）、`VALIDATION_FAILED`（`token` がない）
- **二度押しの対策**：nonce を使用済みにするときに、**値として利用者の ID を書く**（`SET nonce:<nonce> <user_id> NX EX 120`）。書けなかったときは、その値を読み、**同じ利用者なら先に進める**（Visit の一意制約で `already_checked_in` になる）。**別の利用者なら** `TOKEN_ALREADY_USED`。こうしないと、本人が二度押ししただけで「QR を読み直してください」が出てしまう（v0.2 の冪等キー（S2-11）を入れるまでの対策）

### 13. ヘルスチェック（`/v1` の外）

| | |
| --- | --- |
| **GET** `/healthz` | ALB（プロセスが生きていれば、いつも 200。DB は見ない） |
| **GET** `/readyz` | 監視・デプロイの確認（DB・Valkey・SQS につながれば 200、だめなら 503 `SERVICE_UNAVAILABLE`） |

## API の外：公開ページの作り直し（Vercel 側）

| | |
| --- | --- |
| **POST** `https://app.sento-stamprally.com/api/revalidate` | API（7 の保存のあと）だけ |

- ヘッダー `x-revalidate-secret`（Secrets Manager と Vercel の両方に置く秘密の値）。合わなければ 401
- 本文：`{ "tag": "store:ume-no-yu" }` → `revalidateTag(tag, { expire: 0 })`
- S0-11 の試作（`~/dev/isr-test`）と同じ形

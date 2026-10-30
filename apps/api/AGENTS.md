# AGENTS.md — バックエンド（apps/api）

`apps/api` の中では、リポジトリ全体のルール（`/AGENTS.md`）に加えて、このルールを守る。

## 前提

| 項目 | 使うもの |
| --- | --- |
| フレームワーク | Hono（Node.js、`@hono/node-server`） |
| 言語 | TypeScript（strict） |
| 入力の検証・型 | Zod ＋ `@hono/zod-validator`（共有のスキーマは `@yumeguri/shared`） |
| DB | PostgreSQL 18 ＋ Prisma（アプリ用の DB ユーザー `yumeguri_app` で接続する） |
| キャッシュ | Valkey（ElastiCache）。nonce・回数の上限 |
| キュー・ファイル | Amazon SQS、Amazon S3（ローカルは LocalStack） |
| ログ | pino（JSON を標準出力へ） |
| テスト | Vitest（Hono の `app.request()`） |
| ログイン | Cookie のセッション（`sid`）。DB の `Session.token_hash` で探す |

## 基本方針

- コードは**読まれることを前提**に書く。命名・構造・レイヤーの分け方を常に意識する
- 「明示的・簡素・予測できる」TypeScript を書く。魔法のような書き方（デコレーター・暗黙の DI）を使わない
- 新しいファイルを作る前に、既存の命名・ディレクトリの構成を確認し、そろえる
- **テスト駆動（TDD）**：機能を作る前にテストを書く
- 約束ごと（エンドポイント・状態コード・エラーコード）は `docs/api.md`、DB は `docs/erd.md`、権限は `docs/authz-cases.md` に従う

---

## 型の安全性

- `any`・`as`・`as never`・`@ts-ignore`・`@ts-expect-error` は**使わない**
- `unknown` は、外から来た値（`JSON.parse`・SQS のメッセージ・DB の JSON 列）を受ける場所だけ。受けたらすぐ Zod で `parse` する
- 型は Zod のスキーマから `z.infer` で作る。同じ形の `interface` を手で書かない
- ハンドラーの入力の型は、**バリデーター（`zValidator`）から推論させる**。ハンドラーの中で `as` で型を付けない
- `Parameters<...>[0]` のような型の抜き出しで Service の引数の型を作らない。スキーマから共有する
- 画面と共有するスキーマ（リクエスト・レスポンス・エラーコード・`ProblemDetails`・`CursorPage`）は `@yumeguri/shared` に置き、`apps/api` で作り直さない

---

## ディレクトリの構成

```
apps/api/src/
├── index.ts              # 起動（環境変数の検証 → サーバーの起動 → SIGTERM で正しく止める）
├── app.ts                # Hono のアプリの組み立て（ミドルウェア → ルート → onError）
├── routes/               # ルートの定義（何のパスに、何のハンドラーか）
│   ├── index.ts          #   全部のルートをまとめる（ここを見れば全エンドポイントが分かる）
│   ├── stores.ts
│   ├── stores.handler.ts #   ハンドラー（ルートと同じディレクトリ）
│   ├── checkins.ts
│   └── health.ts         #   /healthz・/readyz（/v1 の外）
├── services/             # 業務のロジック・権限の判定・トランザクションの範囲
├── repositories/         # DB へのアクセス（インターフェース ＋ Prisma の実装）
├── domain/               # ドメインの型と純粋な関数（状態の遷移、JST の日付の計算など）
├── adapters/             # 外部のサービス（S3・SQS・Valkey・Secrets Manager）のインターフェース ＋ 実装
├── authz/                # 権限の判定（authorize と、権限の表）
├── middleware/           # 相関 ID・ログ・セッション・CSRF などの横断的な処理
├── errors/               # AppError と、その種類
├── factories/            # Service・Repository・Adapter の組み立て（DI の代わり）
├── config/               # 環境変数の検証・設定
└── utils/                # 純粋な関数（副作用なし）
```

依存の向き：`routes → services → repositories / adapters → (Prisma・AWS SDK)`。`domain`・`utils` はどの層からも使ってよいが、`domain`・`utils` からほかの層を import しない。

---

## ルートの定義 — 一覧できること

- **`routes/index.ts` を見れば、全エンドポイントが一覧できる**こと
- ルートのファイルは、`new Hono()` から**メソッドチェーンで**定義して export する
- パスは `docs/api.md` のとおり（`/v1/...`、ケバブケース・複数形。例：`/v1/staff/stores/:id/checkin-tokens`）

```ts
// routes/index.ts
const v1 = new Hono<AppEnv>()
  .route('/auth', authRoutes)
  .route('/me', meRoutes)
  .route('/stores', storeRoutes)
  .route('/owner/stores', ownerStoreRoutes)
  .route('/staff/stores', staffStoreRoutes)
  .route('/checkins', checkinRoutes)
  .route('/jobs', jobRoutes);

export const routes = new Hono<AppEnv>()
  .route('/', healthRoutes)   // /healthz・/readyz
  .route('/v1', v1);
```

```ts
// routes/stores.ts
export const storeRoutes = new Hono<AppEnv>()
  .get('/', ...listStoresHandlers)
  .get('/:slug', ...getStoreHandlers);
```

### メソッドチェーンが必須の理由

Hono は、`.get()`・`.post()`・`.route()`・`.use()` の**戻り値に型を積み重ねていく**。別の文で呼ぶと戻り値が捨てられ、型が失われる。

```ts
// 良い例
const storeRoutes = new Hono<AppEnv>()
  .get('/', ...listStoresHandlers)
  .get('/:slug', ...getStoreHandlers);

// 悪い例 — 別の文に分けると、型が積み重ならない
const storeRoutes = new Hono<AppEnv>();
storeRoutes.get('/', ...listStoresHandlers);
```

- 画面は、Hono の RPC クライアント（`hc`）ではなく、**`@yumeguri/shared` の Zod スキーマ ＋ fetch** で API を呼ぶ（`apps/web/AGENTS.md`）。そのため `AppType` の export は今は不要

---

## ハンドラー — 受け取って、Service を呼んで、返すだけ

- ハンドラーは `*.handler.ts` に置き、**`factory.createHandlers()` で、バリデーターとハンドラーを一緒に作る**。こうすると、別のファイルに分けても `c.req.valid()` の型が正しく推論される（Hono の公式ドキュメントの推奨。`(c: Context) => …` の関数を別に書くと型が失われる）
- ハンドラーの中でやってよいこと：入力を受け取る → Service を呼ぶ → `return c.json(…, 状態コード)`
- ハンドラーの中に、業務のロジック・DB へのアクセス・データの変換・`try-catch` を書かない

```ts
// routes/factory.ts
export const factory = createFactory<AppEnv>();

// routes/stores.handler.ts
export const getStoreHandlers = factory.createHandlers(
  validate('param', StoreSlugParam),
  async (c) => {
    const { slug } = c.req.valid('param');          // 型が付く
    const store = await storeService.getPublicBySlug(slug);
    return c.json(store, 200);
  },
);

// routes/owner-stores.handler.ts
export const updateStoreHandlers = factory.createHandlers(
  validate('param', StoreIdParam),
  validate('json', UpdateStoreInput),
  async (c) => {
    const { id } = c.req.valid('param');
    const input = c.req.valid('json');
    const store = await storeService.update(c.var.actor, id, input);
    return c.json(store, 200);
  },
);
```

### 入力の検証

- `zValidator` は直接使わず、**`validate()`（`zValidator` を包んだもの）を使う**。検証に失敗したら、`ValidationError` を投げて、**422 ＋ `VALIDATION_FAILED`** の problem+json にする（`zValidator` の初期の動きは 400 で、`docs/api.md` と合わないため）
- 入力のエラーは `errors: [{ path, message }]` で返す

---

## Zod のスキーマ

- リクエスト（パス・クエリ・本文）とレスポンスは、すべて Zod のスキーマで定義する
- 画面と共有するものは `packages/shared` に、API の中だけで使うもの（パスのパラメーターなど）は `apps/api/src/routes/` の近くに置く
- 型は `z.infer` で作る
- 名前は「PascalCase ＋ 役割」：`UpdateStoreInput`・`StoreDetailResponse`・`StoreIdParam`

---

## Service — 業務のロジックの集まり

- 業務のルール・権限の判定・処理の流れ・**トランザクションの範囲**を Service に書く
- DB へのアクセスは Repository に任せる。Service に Prisma のクエリを直接書かない
- 外部のサービス（S3・SQS・Valkey）は、`adapters/` のインターフェースを通して呼ぶ
- **権限の判定は、Service の入口で `authorize(actor, action, resource)` を呼ぶ**（`authz/`）。判定の関数を1か所にまとめ、Service ごとに `if (role === ...)` を書かない
- 「今の時刻」は直接 `new Date()` せず、注入した `Clock` から取る（日付をまたぐテストのため）

```ts
// services/checkinService.ts
export class CheckinService {
  constructor(
    private readonly stores: StoreRepository,
    private readonly visits: VisitRepository,
    private readonly nonces: NonceStore,
    private readonly tokens: CheckinTokenVerifier,
    private readonly clock: Clock,
  ) {}

  async checkIn(actor: Actor, token: string): Promise<CheckinResult> {
    authorize(actor, 'checkin.create');
    const claims = this.tokens.verify(token);                   // TOKEN_INVALID / TOKEN_EXPIRED を投げる
    await this.nonces.claim(claims.nonce, actor.userId);        // 別の人なら TOKEN_ALREADY_USED
    const store = await this.stores.findPublishedById(claims.storeId); // なければ NotFoundError
    const visitedOn = toJstDate(this.clock.now());
    return this.visits.createOnce({
      userId: actor.userId,
      storeId: store.id,
      organizationId: store.organizationId,                     // 利用者が送った値を使わない
      visitedOn,
      source: 'qr',
    });
  }
}
```

---

## テナントの分離（最重要）

- **Repository の、団体のデータを読む関数は、`organizationId` を必須の引数にする**。団体 ID なしで検索できる関数を作らない（例外：公開ページ用の、公開中のデータだけを返す関数）
- 他の団体のデータを指定されたら **404**（`NotFoundError`）。403 にしない（存在を教えない）
- 403 と 404 の決め方は `docs/authz-cases.md` の「403 と 404 の決め方」に従う
- `organization_id` は、**DB から読んだ値**を使う。リクエストの本文やクエリから受け取らない
- 権限のテストは、`docs/authz-cases.md` の表を TypeScript のデータに写し、`test.each` で全部を回す

---

## DI — Factory パターン

- Hono には DI の仕組みがない。**`factories/` で Service・Repository・Adapter を組み立てる**
- ハンドラーの中で `new` しない
- テストでは、Factory を使わずに、モックを直接 Service に渡す

```ts
// factories/index.ts
const prisma = createPrismaClient(env.DATABASE_URL);
const valkey = createValkeyClient(env.VALKEY_URL);

const storeRepository = new PrismaStoreRepository(prisma);
const visitRepository = new PrismaVisitRepository(prisma);
const nonceStore = new ValkeyNonceStore(valkey);

export const checkinService = new CheckinService(
  storeRepository, visitRepository, nonceStore, checkinTokenVerifier, systemClock,
);
```

---

## Repository と Adapter — 置き換えられるように

- 各層は**インターフェース**に依存し、具体的な実装に依存しない
- Prisma は `repositories/` の中に閉じ込める。AWS SDK・Valkey のクライアントは `adapters/` の中に閉じ込める
- Repository は、Prisma のモデルをそのまま返さず、`domain/` の型にして返す
- **DB の制約の違反を、業務の結果に変える**のは Repository の役目（例：Visit の一意制約の違反 `P2002` → `{ result: 'already_checked_in', visit }`）
- トランザクションが要る処理は、Service が範囲を決め、Repository はトランザクションのクライアントを受け取って動く

```ts
// repositories/visitRepository.ts
export interface VisitRepository {
  createOnce(data: NewVisit): Promise<CheckinResult>;
  listByStore(organizationId: string, storeId: string, cursor: Cursor | null): Promise<CursorPage<Visit>>;
}
```

---

## エラーの扱い — try-catch を散らばらせない

- ハンドラーと Service に、個別の `try-catch` を書かない。**`app.onError()` の1か所**で受ける
- 業務のエラーは、**`AppError`（`code`・`status` を持つ）**の子クラスで表し、`throw` する。`code` は `@yumeguri/shared` のエラーコードの一覧から選ぶ
- `app.onError()` は、`AppError` を **RFC 9457 の problem+json**（`type`・`title`・`status`・`code`・`correlationId`・`errors`）に変える
- 予期しないエラーは **500 ＋ `INTERNAL_ERROR`**。レスポンスに、スタックトレース・SQL・例外のメッセージを入れない
- 予期しないエラーをログに出すときも、**例外のオブジェクトをそのまま出さない**（外部の SDK のエラーには、接続文字列や署名つき URL が入っていることがある）。エラーの種類・相関 ID・安全と分かっている項目だけを出す
- `try-catch` を書いてよいのは、**Repository と Adapter で、外部のエラーを業務のエラーや結果に変えるとき**だけ

```ts
// errors/appError.ts
export class AppError extends Error {
  constructor(
    readonly code: ErrorCode,
    readonly status: ContentfulStatusCode,
    message: string,
    readonly errors?: FieldError[],
  ) {
    super(message);
  }
}

export class NotFoundError extends AppError {
  constructor() {
    super('NOT_FOUND', 404, '見つかりません');
  }
}

export class TokenAlreadyUsedError extends AppError {
  constructor() {
    super('TOKEN_ALREADY_USED', 409, 'QR を読み直してください');
  }
}
```

- 「本日はチェックイン済み」は**エラーではない**。200 と `result: "already_checked_in"` で返す（`docs/api.md`）

---

## ミドルウェア

- 横断的な処理（相関 ID・ログ・セッション・CSRF・CORS）はミドルウェアにする
- ミドルウェアも**メソッドチェーンの中**で `.use()` する
- 適用する順番は固定（順番を変えると、エラーのログに相関 ID が付かなくなる）：
  1. 相関 ID（`X-Correlation-Id` を受け取るか作る。レスポンスのヘッダーにも付ける）
  2. 構造化ログ（メソッド・パス・状態コード・かかった時間・相関 ID を JSON で標準出力へ）
  3. セキュリティヘッダー・CORS・CSRF（状態を変えるリクエストで `Origin` を確認）
  4. セッション（`sid` の Cookie → `Session` → `c.set('actor', …)`）

### ログインが必要なルート

- セッションのミドルウェアは、ログインしていなくても `actor` を「ゲスト」として入れるだけにする
- **ログインが必要かどうかは、sub app ごとにチェーンの先頭で `requireLogin` を貼って決める**。誰でも使えるルート（公開ページ・ログインの開始）がある sub app には貼らない

```ts
export const checkinRoutes = new Hono<AppEnv>()
  .use('*', requireLogin)           // この sub app の全部のルートに適用
  .post('/', ...createCheckinHandlers);
```

---

## ログと個人情報

- ログは pino で、**JSON を標準出力**に出す（ECS が CloudWatch Logs に送る）
- **ログに出さないもの**：Cookie・セッションのトークン・パスワード・シークレット・ID トークン・QR のトークン・メールアドレス・IP アドレス（ハッシュにする）
- `console.log` を使わない

---

## 環境変数

- 起動時に Zod で検証する（`packages/shared` の関数）。足りなければ、分かりやすいエラーで起動を止める
- 環境変数を読むのは `config/env.ts` だけ。ほかの場所で `process.env` を直接読まない
- `.env.example` をいつも最新にする（値は空）

```ts
// config/env.ts
const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']),
  PORT: z.coerce.number().int().positive().default(3001),
  DATABASE_URL: z.string().url(),
  VALKEY_URL: z.string().url(),
  WEB_ORIGIN: z.string().url(),
});

export const env = parseEnv(EnvSchema, process.env);
```

---

## 運用のための決まりごと

- `GET /healthz` は**いつも 200**（DB を見ない。ALB のヘルスチェック用）。`GET /readyz` は DB・Valkey・SQS につながるかを見て、だめなら 503
- SIGTERM を受けたら、新しいリクエストの受け付けをやめ、処理中のリクエストを終えてから止まる
- マイグレーションは、マイグレーション用の DB ユーザー（`yumeguri_migrator`）で実行する。アプリはアプリ用のユーザー（`yumeguri_app`）で動く
- `AuditLog` は追記だけ（アプリ用のユーザーには UPDATE・DELETE の権限がない）

---

## テスト（TDD）

- **テストを先に書き、通る実装をあとから書く**
- 優先度：Service のユニットテスト（Repository・Adapter はモック）→ 権限のテスト（`docs/authz-cases.md`）→ ルートの結合テスト（`app.request()`）
- **DB の制約に頼る処理**（Visit の一意制約・部分インデックス・CHECK 制約）は、モックではなく、**本物の PostgreSQL（Docker）で Repository のテスト**をする
- 同時実行のテスト（同じ人の10件同時のチェックイン → Visit がちょうど1件）は、繰り返し実行して確かめる
- 時刻は `Clock` のモックで固定する（JST の 23:59 と 0:00）

```ts
const createMockVisitRepository = (): VisitRepository => ({
  createOnce: vi.fn(),
  listByStore: vi.fn(),
});

describe('CheckinService.checkIn', () => {
  it('別の利用者が使った QR なら TokenAlreadyUsedError を投げる', async () => {
    // ...
    await expect(service.checkIn(visitor, token)).rejects.toThrow(TokenAlreadyUsedError);
  });
});
```

```ts
describe('PATCH /v1/owner/stores/:id', () => {
  it('入力が不正なら 422 と VALIDATION_FAILED を返す', async () => {
    const res = await app.request(`/v1/owner/stores/${storeA1.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', Cookie: ownerCookie, Origin: WEB_ORIGIN },
      body: JSON.stringify({ businessHours: [{ weekday: 7, opensAt: '15:00', closesAt: '01:00' }] }),
    });
    expect(res.status).toBe(422);
    expect(await res.json()).toMatchObject({ code: 'VALIDATION_FAILED' });
  });
});
```

- 条件の多い処理は、**デシジョンテーブル**で網羅していることを示す

| トークン | nonce | 店 | 同じ日の来訪 | 期待する結果 |
| --- | --- | --- | --- | --- |
| 正しい | 未使用 | 公開中 | なし | 201 `checked_in` |
| 正しい | 本人が使用済み | 公開中 | あり | 200 `already_checked_in` |
| 正しい | 別の人が使用済み | — | — | 409 `TOKEN_ALREADY_USED` |
| 期限切れ | — | — | — | 400 `TOKEN_EXPIRED` |
| 署名が不正 | — | — | — | 400 `TOKEN_INVALID` |
| 正しい | 未使用 | 下書き | — | 404 `NOT_FOUND` |

---

## 名前の付け方

| 対象 | 規則 | 例 |
| --- | --- | --- |
| ルートのファイル | ドメイン（ケバブケース）`.ts` | `stores.ts`、`owner-stores.ts` |
| ハンドラーのファイル | ルートの名前 ＋ `.handler.ts` | `stores.handler.ts` |
| ハンドラー | camelCase ＋ `Handlers` | `getStoreHandlers` |
| Service | PascalCase のクラス、ファイルは camelCase | `StoreService`（`storeService.ts`） |
| Repository のインターフェース | PascalCase ＋ `Repository` | `StoreRepository` |
| Repository の実装 | `Prisma` ＋ … | `PrismaStoreRepository` |
| Adapter | 技術の名前 ＋ 役目 | `ValkeyNonceStore`、`S3PresignedUploader` |
| Zod のスキーマ | PascalCase ＋ `Input` / `Response` / `Param` / `Query` | `UpdateStoreInput` |
| エラーのクラス | PascalCase ＋ `Error` | `TokenExpiredError` |
| 関数・変数 | camelCase | `findPublishedById` |
| 定数 | UPPER_SNAKE_CASE | `CHECKIN_TOKEN_TTL_SECONDS` |
| DB の列 | snake_case（Prisma では `@map`） | `visited_on` |
| JSON の項目 | camelCase | `visitedOn` |
| API のパス | ケバブケース・複数形 | `/v1/staff/stores/:id/checkin-tokens` |

---

## CI（PR ごと）

- ESLint、型チェック（`tsc --noEmit`）、ユニットテスト ＋ 結合テスト（PostgreSQL・Valkey・LocalStack をサービスのコンテナで起動）、ビルド

---

## セルフチェック（コードを書く前・PR を出す前）

1. `any`・`as`・`as never`・`@ts-ignore` を使っていないか。`unknown` は外から来た値を受ける場所だけか
2. ハンドラーが `factory.createHandlers()` で作られ、「受け取る → Service → `return c.json()`」だけになっているか
3. 入力の検証が `validate()` で、失敗したら 422 `VALIDATION_FAILED` になるか
4. `try-catch` がハンドラー・Service に散らばっていないか（`app.onError()` にまとまっているか）
5. Service に Prisma のクエリを直接書いていないか。外部のサービスを `adapters/` のインターフェースで呼んでいるか
6. **団体のデータを読む Repository の関数が、`organizationId` を必須にしているか**。`organization_id` を DB の値から決めているか
7. 権限の判定が `authorize()` の1か所で、他の団体のデータが 404 になるか
8. 依存の組み立てが `factories/` にまとまっていて、ハンドラーの中で `new` していないか
9. エラーが `AppError` の `code` で表され、problem+json になっているか。500 で内部の詳細を返していないか
10. ログに秘密の値・個人情報を出していないか。例外のオブジェクトをそのまま出していないか
11. 時刻を `Clock` から取っていて、`visitedOn` を JST の日付で計算しているか
12. ルートの定義・ミドルウェアが**メソッドチェーン**で書かれているか。`routes/index.ts` で全エンドポイントが分かるか
13. テストを先に書いたか。DB の制約に頼る処理を、本物の PostgreSQL でテストしたか
14. 新しい環境変数を足したら、`.env.example` と検証スキーマも更新したか。`process.env` を `config/env.ts` 以外で読んでいないか

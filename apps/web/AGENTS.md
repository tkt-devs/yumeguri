# AGENTS.md — フロントエンド（apps/web）

リポジトリ全体のルール（`/AGENTS.md`）に加えて、`apps/web` の中ではこのルールを守る。

## 前提

| 項目 | 使うもの |
| --- | --- |
| フレームワーク | Next.js 16（App Router、Server Components） |
| 言語 | TypeScript（strict） |
| サーバーのデータ | TanStack Query（クライアント）、`'use cache'`（サーバー・ISR） |
| 入力の検証・型 | Zod（共有のスキーマは `@yumeguri/shared`） |
| スタイル | CSS Modules ＋ CSS 変数（**Tailwind は使わない**。ADR-010） |
| テスト | Vitest ＋ Testing Library |
| ログイン | Cookie のセッション（HttpOnly）。**トークンを JavaScript で持たない** |

## 基本方針

- コードは**読まれることを前提**に書く。命名・構造・レイヤーの分け方を常に意識する
- 新しいファイルを作る前に、既存の命名・ディレクトリの構成を確認し、そろえる
- 「動く」ではなく、「意図が伝わり、テストでき、置き換えられる」コードを書く
- レイヤーの境界を破らない。迷ったらこのドキュメントに従う

---

## ディレクトリの構成とレイヤー

```
apps/web/src/
├── app/                        # ルーティング（Next.js App Router）。最上層・最も薄い
│   ├── layout.tsx
│   ├── error.tsx / not-found.tsx
│   ├── (public)/                   # 誰でも見られる画面
│   │   ├── stores/page.tsx             # 銭湯の一覧（SCR-02、Server Component）
│   │   └── stores/[slug]/page.tsx      # 銭湯の詳細（SCR-03、ISR）
│   ├── (visitor)/                  # ログインした来訪者の画面
│   │   └── checkin/page.tsx            # チェックイン（SCR-08）
│   ├── (staff)/                    # スタッフ・オーナーの画面
│   │   ├── owner/stores/[id]/page.tsx  # 銭湯の編集（SCR-23）
│   │   └── staff/stores/[id]/qr/page.tsx  # QR の表示（SCR-20）
│   ├── (admin)/                    # 団体・システムの管理者の画面
│   └── api/revalidate/route.ts     # Route Handler（公開ページの作り直し）
│
├── api/                        # API 通信の層（最下層）
│   ├── client/                 #   fetch の共通処理
│   │   ├── client.ts           #     baseURL・Cookie・JSON・タイムアウト
│   │   ├── apiError.ts         #     problem+json → ApiError への変換
│   │   └── index.ts
│   ├── schemas/                #   レスポンス・リクエストの Zod スキーマと型
│   │   ├── store.ts            #     @yumeguri/shared を再エクスポート ＋ 画面だけのもの
│   │   └── common.ts           #     CursorPage・ProblemDetails など
│   ├── mappers/                #   レスポンスの正規化・型の変換
│   │   └── storeMapper.ts
│   └── endpoints/              #   ドメインごとの API の関数
│       ├── storeApi.ts         #     クライアントから呼ぶもの
│       └── storeApi.server.ts  #     Server Component から呼ぶもの（'use cache' を含む）
│
├── hooks/                      # カスタムフック（クライアント専用）
│   └── [domain]/
│       ├── queries/            #   データの取得（useQuery のラッパー）
│       └── mutations/          #   データの変更（useMutation のラッパー）
│
├── components/
│   ├── ui/                     #   汎用の部品（ドメインの知識を持たない）
│   ├── domain/                 #   ドメインの表示（Presentational）
│   └── container/              #   hooks を呼び、domain に渡す（'use client'）
│
├── providers/                  # Context Provider（QueryClientProvider など）
├── validation/                 # 画面の入力の Zod スキーマ（送信できるかの判定）
├── styles/                     # 全体の CSS（リセット・CSS 変数・ダークモード）
├── constants/                  # 定数（エラーメッセージの対応表を含む）
├── types/                      # 画面だけの型
└── utils/                      # 純粋な関数（副作用なし。日付の JST への変換など）
```

---

## サーバーとクライアントの分け方（Next.js）

| 画面の種類 | データの取り方 | 例 |
| --- | --- | --- |
| 公開ページ（誰でも見る・キャッシュする） | **Server Component** で `api/endpoints/*.server.ts` を `await` する | 銭湯の一覧・詳細 |
| ログインして操作する画面 | **Client Component**（Container）で TanStack Query の hooks を使う | 銭湯の編集、QR の表示、チェックイン |

- `'use client'` を付けるのは、**Container と、操作のある ui の部品だけ**。ページ（`page.tsx`）や domain には付けない
- Server Component の `page.tsx` は、`*.server.ts` の関数を呼んで、domain のコンポーネントに渡すだけにする（このときは page が Container の役をする）
- 秘密の値（作り直しの秘密のヘッダーなど）を使うファイルの先頭に `import 'server-only';` を書く。クライアントに混ざるとビルドで止まる
- 公開ページのキャッシュは `'use cache'` ＋ `cacheLife()` ＋ `cacheTag()`。作り直しは `revalidateTag(tag, { expire: 0 })`。タグの名前は `constants/cacheTags.ts` の関数で作る（例：`storeTag(slug)` → `store:ume-no-yu`）
- 環境変数のうち、ブラウザに出してよいものだけ `NEXT_PUBLIC_` を付ける。秘密の値に `NEXT_PUBLIC_` を付けない

---

## 型の安全性

- `any`・`as`・`as never`・`@ts-ignore`・`@ts-expect-error` は**使わない**
- `unknown` は **`api/client/` と `api/endpoints/` の中だけ**（`response.json()` の戻り値を受けるため）。受けたらすぐ Zod で `parse` する
- 型は Zod のスキーマから `z.infer` で作る。同じ形の `type` や `interface` を手で書かない（二重管理しない）
- 画面と API で共有するスキーマ（エラーコード・`ProblemDetails`・`CursorPage` など）は `@yumeguri/shared` から import する。`apps/web` で同じものを作り直さない
- 画面だけの型は、`&` や `Omit` / `Pick` で、共有の型を広げて作る

```ts
// api/schemas/store.ts
export { StoreDetail, StoreSummary } from '@yumeguri/shared';
```

---

## 値の扱い

- falsy な値（`""`・`0`・`null`・`undefined`）の初期値を、あちこちで決めない。**`api/mappers/` の1か所**で決める
- オブジェクト・配列のコピーと合成はスプレッド構文（`...`）を使う
- `?.` のネストは2段まで。それ以上になるなら mapper で形を整える
- 日時は API から UTC の ISO 8601 で来る。**JST の表示への変換は `utils/date.ts` だけ**で行う。来訪の日付（`visitedOn`）は、もともと JST の日付なので変換しない

```ts
// api/mappers/storeMapper.ts
export const normalizeStoreSummary = (raw: StoreSummaryResponse): StoreSummary => ({
  ...raw,
  thumbnailUrl: raw.thumbnailUrl ?? STORE_PLACEHOLDER_IMAGE,
});
```

---

## レイヤーの import の制約

依存の向きは**上から下への一方通行**。下の層が上の層を import しない。

```
app → container → hooks/queries, hooks/mutations → api/endpoints → api/schemas, api/mappers, api/client
    → domain     → ui
    → api/endpoints/*.server.ts（Server Component の page だけ）
```

| 層 | import してよいもの |
| --- | --- |
| `app/` | container、domain、providers、`api/endpoints/*.server.ts`、constants |
| `components/container/` | hooks、domain、ui、providers、validation、constants、types、utils |
| `components/domain/` | ui、validation、constants、types、utils（**hooks・api は禁止**） |
| `components/ui/` | constants、types、utils（ほかの層は禁止） |
| `hooks/` | api/endpoints、providers、validation、constants、types、utils（**components は禁止**） |
| `validation/` | constants、types、`@yumeguri/shared` |
| `providers/` | hooks、api/client、constants、types、utils |
| `api/endpoints/` | api/schemas、api/mappers、api/client、constants、utils |
| `api/mappers/` | api/schemas、constants、utils |
| `api/schemas/` | `@yumeguri/shared`、constants、types |
| `api/client/` | api/schemas（`ProblemDetails`）、constants |
| `utils/` | 外部のライブラリと types だけ |

- **同じ層の中の import** は、部品を組み合わせる目的ならどの層でもよい（`ui/ErrorCard` が `ui/Card` を使う、など）。ただし循環させない
- 層をまたぐ制約は ESLint（eslint-plugin-boundaries）で CI が検査する。同じ層の中は検査しないので、レビューで見る

---

## API の層

### `api/client/` — fetch の共通処理

- `fetch` を包んだ `apiFetch` を1つだけ作る。ほかの場所で `fetch` を直接呼ばない
- **Cookie でログインする**ので、`credentials: 'include'` を必ず付ける。トークンを `localStorage` などに保存しない。`Authorization` ヘッダーも使わない
- 2xx 以外のレスポンスは、`application/problem+json` を Zod で検証して **`ApiError`**（`status`・`code`・`correlationId`・`errors`）にして投げる
- 401（`AUTH_REQUIRED`）は、今の URL を `returnTo` に付けてログイン画面へ移す（チェックインの `?t=` を失わないため）

### `api/schemas/` — Zod のスキーマと型

- 型は `z.infer` で作る。ドメインごとに1ファイル ＋ `common.ts`
- 一覧は**カーソル方式**（`{ items, nextCursor }`）。ページ番号の方式の型を作らない

### `api/mappers/` — レスポンスの正規化

- API のレスポンスを画面用の型に変える、**唯一の場所**
- 純粋な関数にする（副作用なし）。テストを必ず書く

### `api/endpoints/` — API の関数

- ドメインごとに1ファイル。`apiFetch` で呼び、スキーマで `parse` し、mapper で整えて返す
- hooks から呼ばれる、唯一の入口
- Server Component 用は `*.server.ts` に分け、`import 'server-only';` を書く

```ts
// api/endpoints/storeApi.ts
export const storeApi = {
  getForOwner: async (id: string): Promise<OwnerStore> => {
    const json = await apiFetch(`/v1/owner/stores/${id}`);
    return normalizeOwnerStore(OwnerStoreResponse.parse(json));
  },
  update: async (id: string, input: UpdateStoreInput): Promise<OwnerStore> => {
    const json = await apiFetch(`/v1/owner/stores/${id}`, { method: 'PATCH', body: input });
    return normalizeOwnerStore(OwnerStoreResponse.parse(json));
  },
};
```

---

## hooks — queries と mutations

- `hooks/[domain]/queries/`：`useQuery` のラッパー。**読むだけ**。1ファイル1フック
- `hooks/[domain]/mutations/`：`useMutation` のラッパー。**書くだけ**。成功したときのキャッシュの無効化までを受け持つ。1ファイル1フック
- query と mutation を1つのファイルに混ぜない
- hooks の中で画面の状態（モーダルの開閉など）を持たない。それは Container が持つ
- `queryKey` は `constants/queryKeys.ts` の関数で作る（直書きしない）
- **一定時間ごとに取り直す処理は `refetchInterval` を使う**（例：QR のトークンを30秒ごとに取り直す）。`useEffect` ＋ `setInterval` で書かない

```ts
// hooks/checkin/queries/useCheckinToken.ts
export const useCheckinToken = (storeId: string) => {
  const query = useQuery({
    queryKey: queryKeys.checkinToken(storeId),
    queryFn: () => checkinApi.issueToken(storeId),
    refetchInterval: CHECKIN_TOKEN_REFRESH_MS,
    refetchIntervalInBackground: false,
  });
  return { token: query.data, isLoading: query.isLoading, error: query.error };
};
```

---

## コンポーネント — Container / Domain / UI の3層

| 層 | 役目 | してはいけないこと |
| --- | --- | --- |
| **ui** | 汎用の見た目の部品（Button・Input・Card・Spinner・Badge） | ドメインの知識を持つ、hooks・API を呼ぶ |
| **domain** | ドメインの表示（StoreCard・BusinessHoursTable・CheckinResult）。props で受け取って表示するだけ | hooks・API を呼ぶ。イベントは props のコールバックで上に渡す |
| **container** | hooks を呼んで、domain・ui に props を渡す（`'use client'`） | スタイルを書く。表示の分岐（読み込み中・エラー・空）は書いてよい |

判断の基準：

```
hooks を呼ぶ？                   → container
ドメインのデータを props で受ける？ → domain
どちらでもない汎用の部品？         → ui
```

### ファイルの置き方（コロケーション）

- **1コンポーネント = 1ディレクトリ**。テストを同じディレクトリに置く（`__tests__/` に分けない）
- `index.ts` は再エクスポートだけ。ロジックを書かない
- Storybook は使わない（`.stories.tsx` を置かない）

```
StoreCard/
├── StoreCard.tsx
├── StoreCard.test.tsx
├── StoreCard.module.css
└── index.ts
```

### ページ（`app/**/page.tsx`）

- **一番薄い層**。Container（または Server Component のデータと domain）を置くだけ
- ルートのパラメーター（`params`・`searchParams`）を受け取って渡す以外の処理を書かない
- Next.js 16 では `params`・`searchParams` は Promise。`await` してから使う

```tsx
// app/owner/stores/[id]/page.tsx
export default async function OwnerStorePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <OwnerStoreEditorContainer storeId={id} />;
}
```

---

## 状態の管理

| データ | 置き場所 |
| --- | --- |
| サーバーのデータ | TanStack Query（`hooks/`）または Server Component |
| アプリ全体の設定（QueryClient など） | Context（`providers/`） |
| 画面の中の状態（入力中の値・モーダル） | `useState` / `useReducer`（Container の中） |

- `useState` ＋ `useEffect` ＋ `fetch` でデータを取らない
- サーバーのデータを Context に入れない
- **ログインしている人の情報も、Context ではなく `GET /v1/me` の query** で持つ

---

## React の書き方

### useEffect の制限

- 使ってよいのは次の場合だけ：
  1. ブラウザの API との同期（`addEventListener`、Wake Lock、`IntersectionObserver` など）
  2. 外部のライブラリの初期化と後片付け
  3. `ref` を通した DOM の操作
- それ以外は、別の方法を使う：派生する値 → 描画の中で計算／`useMemo`、イベントで起きる処理 → イベントハンドラーの中、データの取得 → TanStack Query、定期的な取り直し → `refetchInterval`
- 使うときは、**「なぜ Effect が必要か」をコメントに書く**。後片付け（return の関数）を必ず書く

```ts
// Why Effect: QR を表示している間、タブレットの画面が消えないようにする（Wake Lock API との同期）
useEffect(() => {
  const lock = navigator.wakeLock?.request('screen');
  return () => { void lock?.then((l) => l.release()); };
}, []);
```

### コンポーネントの設計

- 1つのコンポーネントに1つの役目。1ファイル1コンポーネント
- props が5個を超えたら、まとめるか、分けることを考える
- props のバケツリレーは2段まで

---

## エラーの扱い

- API のエラーは `api/client/` で `ApiError` にそろえる。コンポーネントや hooks の中で、個別に `try-catch` しない
- 表示の文言は、**`ApiError.code` を見て** `constants/errorMessages.ts` の対応表から選ぶ。`title` の文章で判定しない
- 入力のエラー（`VALIDATION_FAILED`）は、`errors[].path` を見て、項目のそばに出す
- 予期しないエラー（500）は、相関 ID（`correlationId`）を画面に出す（問い合わせのときにログを追えるように）
- 画面の単位のエラーは `error.tsx`（Error Boundary）で受ける
- **「本日はチェックイン済み」はエラーではない**。200 の `result: "already_checked_in"` で表示を分ける

---

## アクセシビリティと見た目

- 意味のある HTML を使う（`header`・`nav`・`main`・`article`・`button`・見出しの階層）。押せるものは `div` ではなく `button` か `a`
- **スマホの幅（320px）を基準に作る**。320px で横スクロールが出ないこと
- 操作の結果（保存した・チェックインした）は `aria-live` で読み上げソフトにも伝える
- オーナー・スタッフ向けの画面は、**文字を大きく、操作を少なく**（ペルソナの田中さん）
- スタイルは **CSS Modules**（`*.module.css`）でコンポーネントと同じディレクトリに置く。`style` 属性を直書きしない
- 色・余白・文字の大きさ・角丸は、`styles/` の **CSS 変数**（`var(--color-primary)` など）を使う。値を直書きしない
- レイアウトは Flexbox と CSS Grid。スマホを基準に書き、広い画面は `@media (min-width: …)` で足す

---

## 定数とマジックナンバー

- マジックナンバー・マジックストリングは `constants/` にまとめる

```ts
// constants/checkin.ts
export const CHECKIN_TOKEN_REFRESH_MS = 30_000;

// constants/roles.ts
export const MEMBERSHIP_ROLES = ['staff', 'owner', 'org_admin'] as const;
```

---

## 名前の付け方

| 対象 | 規則 | 例 |
| --- | --- | --- |
| コンポーネントのディレクトリ・ファイル | PascalCase | `StoreCard/StoreCard.tsx` |
| Container | PascalCase ＋ Container | `OwnerStoreEditorContainer.tsx` |
| テスト | 本体の名前 ＋ `.test` | `StoreCard.test.tsx` |
| query の hook | use ＋ ドメイン | `useStore.ts`、`useCheckinToken.ts` |
| mutation の hook | use ＋ 動詞 ＋ ドメイン | `useUpdateStore.ts`、`useCheckIn.ts` |
| API | camelCase ＋ Api | `storeApi.ts`、`storeApi.server.ts` |
| mapper | camelCase ＋ Mapper | `storeMapper.ts` |
| schema | camelCase（`api/schemas/` の中） | `store.ts` |
| Provider | PascalCase ＋ Provider | `QueryProvider.tsx` |
| 関数・変数 | camelCase | `normalizeStore` |
| 型 | PascalCase | `StoreDetail` |
| 定数 | UPPER_SNAKE_CASE | `CHECKIN_TOKEN_REFRESH_MS` |
| イベントハンドラー | handle ＋ 動詞 | `handleSubmit` |
| boolean | is / has / can ＋ … | `isLoading`、`canEdit` |
| スタイル | 本体の名前 ＋ `.module.css` | `StoreCard.module.css` |
| CSS のクラス | camelCase（CSS Modules で `styles.cardTitle` と書けるように） | `.cardTitle` |
| ルートのディレクトリ（`app/`） | kebab-case。ルートグループは `(名前)` | `app/(staff)/owner/stores/[id]/` |

---

## テスト

| 対象 | テスト | 必須か |
| --- | --- | --- |
| `hooks/queries`・`hooks/mutations` | ユニット（API の関数をモックする） | 必須 |
| `api/mappers` | ユニット | 必須 |
| `validation` | ユニット | 必須 |
| container | 結合（hooks ＋ コンポーネント） | 必須 |
| domain | ユニット（表示の分岐・コールバック） | 必須 |
| ui | ユニット（状態ごとの表示・操作できるか） | 必須 |
| `api/endpoints` | （mapper とスキーマのテストで担保する） | — |

- 表示の分岐が多いものは、**デシジョンテーブル**で網羅していることを示す

| ログイン | 結果 | 期待する表示 |
| --- | --- | --- |
| 済み | `checked_in` | 「チェックインしました」 |
| 済み | `already_checked_in` | 「本日はチェックイン済みです」 |
| 済み | `TOKEN_EXPIRED` | 「QR の期限が切れました。もう一度読んでください」 |
| 済み | `TOKEN_ALREADY_USED` | 「QR を読み直してください」 |
| 未 | — | ログイン画面へ（`returnTo` に今の URL） |

## CI（PR ごと）

- ESLint（import の制約を含む）、型チェック（`tsc --noEmit`）、ユニットテスト、ビルド

---

## セルフチェック（コードを書く前・PR を出す前）

1. `any`・`as`・`@ts-ignore` を使っていないか。`unknown` は `api/client`・`api/endpoints` の中だけか
2. import の向きが、レイヤーの制約を破っていないか
3. コンポーネントが正しい層（ui / domain / container）に置かれ、テストが同じディレクトリにあるか
4. domain が hooks・api を import していないか。ui がドメインの知識を持っていないか
5. `page.tsx` が、Container（またはデータと domain）を置くだけの薄さか
6. hooks が queries / mutations に分かれ、画面の状態を持っていないか
7. データの取得が TanStack Query か Server Component で、`useEffect` ＋ `fetch` になっていないか
8. サーバーのデータ（ログインしている人の情報を含む）を Context に入れていないか
9. `useEffect` が許された場合だけで、「なぜ Effect が必要か」のコメントと後片付けがあるか
10. falsy な値の初期値が `api/mappers/` にまとまっているか
11. API の呼び出しが `api/endpoints/` 経由で、レスポンスを Zod で検証し、mapper で整えているか
12. `credentials: 'include'` で Cookie を送り、トークンを JavaScript で持っていないか
13. エラーの表示を `code` で選び、`title` の文章で判定していないか
14. 秘密の値を使うファイルに `import 'server-only';` があり、秘密の値に `NEXT_PUBLIC_` が付いていないか
15. マジックナンバー・文字列が `constants/` にまとまっているか。`queryKey`・キャッシュのタグが関数で作られているか
16. 入力の受け付けのルール・送信できるかの判定が `validation/` の Zod スキーマにまとまっているか
17. 320px で崩れず、意味のある HTML になっているか。色・余白を直書きせず CSS 変数を使っているか
18. 新しい環境変数を足したら、`.env.example` と検証スキーマも更新したか

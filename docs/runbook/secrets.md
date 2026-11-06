# シークレットの値を入れる

Terraform（`envs/staging-persistent`）は、シークレットの **入れ物** だけを作る。値を Terraform に書くと、state のファイルに平文で残るため（ADR-015）。値は、作った後に、次のどちらかで入れる。

## 入れ物の一覧（staging）

| 名前 | 中身 | 値を入れる時期 |
| --- | --- | --- |
| `yumeguri/staging/google-oauth` | Google のクライアント ID とシークレット（JSON：`{"client_id": …, "client_secret": …}`） | Google のログインを作るとき |
| `yumeguri/staging/sentry-dsn` | Sentry の DSN | S1-20 |
| `yumeguri/staging/qr-signing-key` | QR の署名の鍵（JSON：`{"kid": …, "key": …}`） | QR のチェックインを作るとき |
| `yumeguri/staging/session-secret` | セッションの Cookie の鍵 | ログインを作るとき |

DB のユーザーのパスワード（`yumeguri/staging/db/…`）と、Valkey の合言葉（`yumeguri/staging/valkey-auth`）は、Terraform（`envs/staging`）が値まで入れる（state には残らない）。手で入れない。

## CLI で入れる

値を、シェルの履歴に残さない。ファイルから読ませて、すぐ消す。

```bash
export AWS_PROFILE=yumeguri
# 1. 値をファイルに書く（エディタで。画面に出さない・スクリーンショットを撮らない）
# 2. 入れる
aws secretsmanager put-secret-value \
  --secret-id yumeguri/staging/sentry-dsn \
  --secret-string file://secret.txt
# 3. ファイルを消す
rm secret.txt
```

## 管理画面で入れる

Secrets Manager → シークレット → 名前を選ぶ →「シークレットの値を取得する」→「編集する」。

## 注意

- 入れ物を消しても、30日は戻せる（`recovery_window_in_days`）。その間は、同じ名前で作り直せない
- 値は、使っていなくても、シークレット1つにつき月 0.40 ドルかかる

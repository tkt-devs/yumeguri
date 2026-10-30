# ADR-024: 入口は Cloudflare（DNS・WAF・API のプロキシ）にし、画像は CloudFront で配る

- 状態：決定
- 日付：2026-10-30

## 背景

ドメインの DNS、API の入口の守り（WAF・レート制限）、画像の配信を、どのサービスで行うかを決める。

## 選択肢

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| Cloudflare（DNS・WAF・プロキシ）＋ CloudFront（画像） | Cloudflare の無料のプランで、DNS・WAF・レート制限が使える。画像は CloudFront の OAC で、S3 を非公開のまま配れる | AWS の外のサービスが入る。無料のプランには上限がある |
| Route 53 ＋ CloudFront ＋ AWS WAF にすべて寄せる | AWS の中で完結し、SAA の範囲そのもの | AWS WAF は、ルールの数とリクエストの数で費用がかかる。Route 53 もホストゾーンごとに費用がかかる |

## 決めたこと

- DNS は **Cloudflare**（ドメインも Cloudflare Registrar で取得した）
- `api.` は Cloudflare の **プロキシを有効**（オレンジの雲）にし、WAF・レート制限・秘密のヘッダー（ADR-013）を使う。`api.` はキャッシュしない
- `img.` は **CloudFront**（OAC）で、公開用のサムネイルのバケットから配る。Cloudflare のプロキシは使わない（CDN を二重にしない）
- `app.` は Vercel（ADR-001）。Cloudflare のプロキシは使わない

## 理由

- S0-11 で、Cloudflare の無料のプランの範囲（WAF のルール5つ・レート制限のルール1つ・リクエストヘッダーを付けるルール）で、必要なことができると確かめた
- 費用がほぼかからない
- 画像の配信（CloudFront・OAC）は、SAA でよく出るので、AWS で作る

## 捨てた選択肢

- **すべて AWS に寄せる**：AWS WAF と Route 53 の費用がかかるので採らない。SAA の学習のために、AWS WAF の考え方は、Cloudflare の WAF と比べてノートに書く

## リスクと、その対策

- 無料のプランのレート制限は1つだけ。一番大事な1か所（ログインか、公開 API）に使い、ほかの回数の上限は API 側（ElastiCache）で行う
- Cloudflare の SSL の設定は **Full (strict)** にする。Flexible のままだと、Cloudflare と ALB の間が暗号化されない

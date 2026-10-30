# 設計判断の記録（ADR）

設計で「なぜそう決めたか」を残す。あとから読んだ人（未来の自分を含む）が、同じ議論をくり返さずに済むようにする。

- 新しく書くときは [000-template.md](000-template.md) をコピーする
- 一度決めた ADR は書き換えない。考えを変えたときは、新しい ADR を書き、古い ADR の状態を「廃止（ADR-YYY に置き換え）」にする
- 番号は要件定義書の ADR の一覧に合わせる。006〜009・016・023 は、その機能を作るときに書く。014（メール）・021（機能フラグ）は、その機能を作らないので書かない

| ADR | 決めたこと |
| --- | --- |
| [ADR-001](001-web-on-vercel.md) | Web（Next.js）を Vercel で動かす |
| [ADR-002](002-ecs-fargate-arm.md) | API とワーカーを ECS（Fargate・ARM）で動かす |
| [ADR-003](003-cookie-and-cors.md) | Web と API を別のサブドメインにしたときの Cookie と CORS |
| [ADR-004](004-session-cookie.md) | ログインの状態を、セッションの Cookie で持つ |
| [ADR-005](005-python-worker.md) | ワーカーを Python にし、DB のスキーマは Prisma だけが管理する |
| [ADR-010](010-css-modules.md) | CSS は CSS Modules ＋ CSS 変数にする |
| [ADR-011](011-rds-postgresql.md) | DB は RDS for PostgreSQL にする |
| [ADR-012](012-sqs-and-elasticache.md) | ジョブのキューは SQS、キャッシュ・nonce は ElastiCache（Valkey）にする |
| [ADR-013](013-egress-and-origin-protection.md) | 外への出口は NAT の EC2 にし、ALB は Cloudflare からだけ届くようにする |
| [ADR-015](015-secrets-manager-and-qr-key.md) | シークレットは Secrets Manager に置き、QR の署名の鍵もそこに置く |
| [ADR-017](017-monitoring.md) | 監視は、v0.1 は CloudWatch と Sentry にし、X-Ray は v0.2 で足す |
| [ADR-018](018-self-implemented-oidc.md) | Google のログイン（OIDC）を自分で実装する |
| [ADR-019](019-rds-single-az.md) | RDS は Single-AZ にする |
| [ADR-020](020-local-emulator.md) | ローカルの S3・SQS の代わりに LocalStack（Hobby）を使う |
| [ADR-022](022-accounts-and-on-demand.md) | AWS のアカウントを staging と production で分け、どちらも使うときだけ作る |
| [ADR-024](024-cloudflare-and-cloudfront.md) | 入口は Cloudflare（DNS・WAF・API のプロキシ）にし、画像は CloudFront で配る |

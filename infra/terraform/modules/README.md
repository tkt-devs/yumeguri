# modules

staging・production で同じものを作るための部品を置く。

| 部品 | 作るもの | 手順書 |
| --- | --- | --- |
| `network` | VPC・サブネット4つ・インターネットゲートウェイ・ルートテーブル・NAT の代わりの EC2（ADR-013）・S3 のゲートウェイエンドポイント・セキュリティグループ5つ（＋ NAT の EC2 用） | S1-13 |
| `buckets` | S3 のバケット3つ（非公開・公開用サムネイル・ログ）。パブリックアクセスのブロック・暗号化・HTTPS だけ・ライフサイクル・CORS・CloudFront と ALB のログの許可 | S1-14・S1-16 |
| `queues` | SQS の `jobs-default`・`jobs-heavy` と、それぞれの DLQ。このアカウント以外を断るポリシー | S1-14 |
| `app_secrets` | シークレットの入れ物（値は Terraform の外で入れる） | S1-14 |
| `rds` | RDS for PostgreSQL・サブネットグループ・パラメータグループ、DB のユーザーのパスワード（state に残さない） | S1-14 |
| `valkey` | ElastiCache for Valkey（TLS・AUTH トークン。トークンは state に残さない） | S1-14 |
| `ecr` | ECR のリポジトリ（タグの上書きなし・押し上げたときのスキャン・古いイメージを消すルール） | S1-15 |
| `iam_ecs` | ECS のタスク実行ロール・API のタスクロール・ワーカーのタスクロール | S1-15 |
| `ecs` | ECS のクラスター・ロググループ・タスク定義（API・ワーカー）・サービス | S1-15 |
| `alb` | ALB・ターゲットグループ（`/healthz`）・HTTPS のリスナー（秘密のヘッダーがなければ 403）・アクセスログ | S1-15・S1-16 |
| `acm_cert` | ACM の証明書と、Cloudflare に作る DNS の検証用のレコード | S1-16 |
| `edge` | Cloudflare のゾーンの設定（Full (strict)）・ルール（秘密のヘッダー・キャッシュしない・Webhook を WAF から外す）・秘密のヘッダーの値（Secrets Manager） | S1-16 |
| `cdn` | CloudFront・OAC・`img.` の DNS（灰色の雲） | S1-16 |

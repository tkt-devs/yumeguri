# infra/terraform

AWS に作るもの（staging・production の環境）を、コードで書いておく場所。

```
infra/terraform/
├── bootstrap/      # 最初に1回だけ作るもの：state を置く S3 のバケット
├── modules/        # staging・production で同じものを作るための部品（S1-13 から）
└── envs/
    ├── staging-persistent/  # staging の「ずっと残す層」：S3・SQS・シークレットの入れ物（S1-14）
    └── staging/             # staging の「使うときだけの層」：VPC・NAT・RDS・ElastiCache（S1-13・S1-14）
```

- 2つの層は、**state を別々に** 置く（ADR-022）。`staging` を `destroy` しても、`staging-persistent`（アップロードされたファイル・手で入れたシークレットの値）は消えない
- **お金**：`staging` の RDS・ElastiCache・NAT は、置いているだけで1時間ごとに費用がかかる（合わせて月 約44ドル）。使わないときは消す（S1-19 で `up` / `down` にまとめる）

- **state**：Terraform が AWS に作ったものの記録。S3 のバケット `yumeguri-tfstate-<環境>` に置く（バージョニング・暗号化・パブリックアクセスのブロック・HTTPS だけ）
- **ロック**：同時に2人が apply しないように、S3 にロックのファイルを置く（`use_lockfile`。DynamoDB の表は使わない）
- **CI**：`fmt -check` と `validate` だけ（AWS にはつながない）。`plan`・`apply` は手元で行う
- **版**：Terraform は `mise.toml`（`versions.tf` の `required_version` と同じ範囲）、AWS プロバイダーは `versions.tf` と `.terraform.lock.hcl`

## 準備

```bash
# Terraform（mise.toml の版）を入れる。リポジトリのいちばん上で
mise install

# AWS にログインする（ブラウザで「My First Project」→ AccountFullAccessRole を選ぶ）
aws login --profile yumeguri
export AWS_PROFILE=yumeguri

# つながっているアカウントを確かめる（staging の ID か）
aws sts get-caller-identity --query Account --output text
```

# Cloudflare の API トークンを、キーチェーンから環境変数に入れる（画面にもファイルにも出さない）
export CLOUDFLARE_API_TOKEN=$(security find-generic-password -s yumeguri-cloudflare-api-token -w)
```

### Cloudflare の API トークン（最初の1回）

Cloudflare のダッシュボード →「My Profile」→「API Tokens」→「Create Token」→「Custom token」で作る。

- 権限（すべて Zone）：Zone Read・DNS Edit・Zone Settings Edit・Zone WAF Edit・Transform Rules Edit・Cache Rules Edit
- Zone Resources：Include → Specific zone → `sento-stamprally.com`

できたトークンは、Mac のキーチェーンに入れる（入力を求められるので貼り付ける。画面には出ない）。

```bash
security add-generic-password -a "$USER" -s yumeguri-cloudflare-api-token -w
```

各フォルダの `terraform.tfvars.example` を `terraform.tfvars` にコピーして、アカウント ID を入れる。`terraform.tfvars` は Git に入らない。ほかのアカウントにつながっていると、`plan` の時点で止まる（`allowed_account_ids`）。

## ふだんの使い方（envs/staging-persistent・envs/staging）

最初に `staging-persistent`、次に `staging` の順に作る。どちらのフォルダでも同じコマンドを使う。

```bash
cd infra/terraform/envs/staging   # または envs/staging-persistent
terraform init     # 最初の1回と、プロバイダーの版を変えたとき
terraform plan     # 何が変わるかを読む。destroy・replace があれば、理由が分かるまで apply しない
terraform apply
```

### 使い終わったら（費用のかかるものだけ消す）

`envs/staging` で、時間で費用のかかるもの（ECS・ALB・RDS・Valkey）と、ALB を向いている `api.` の DNS を消す。VPC・NAT の EC2 は残る（全部消すときは `terraform destroy`）。

```bash
cd infra/terraform/envs/staging
terraform destroy \
  -target=module.ecs -target=module.alb -target=module.iam_ecs \
  -target=module.rds -target=module.valkey -target=cloudflare_dns_record.api
```

## bootstrap（state のバケット）

ふだんは、バケットの設定を変えるときだけ使う。

```bash
cd infra/terraform/bootstrap
terraform init -backend-config=staging.s3.tfbackend
terraform plan
terraform apply
```

### 最初の1回だけ（バケットがまだないとき）

bootstrap 自身の state を置くバケットは、bootstrap が作る（卵が先か鶏が先かの問題）。そこで、最初だけ state を Mac に置いて作り、作ったあとでバケットに移す。

```bash
cd infra/terraform/bootstrap

# 1. 一時的に、state を Mac に置く設定を足す（*_override.tf は、backend.tf の設定を上書きする。Git に入らない）
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
terraform init
terraform plan -out=tfplan
terraform apply tfplan
rm tfplan

# 2. 一時的な設定を消して、state をバケットに移す（"yes" と聞かれたら yes）
rm backend_override.tf
terraform init -migrate-state -backend-config=staging.s3.tfbackend

# 3. バケットに入ったことを確かめてから、Mac に残った state を消す
aws s3 ls s3://yumeguri-tfstate-staging/bootstrap/
terraform state list
rm terraform.tfstate terraform.tfstate.backup
```

production（S4-01）では、production のアカウントにログインし、`production.s3.tfbackend` と、production の `terraform.tfvars` を作る。そのうえで、上の手順の `staging.s3.tfbackend` を `production.s3.tfbackend` に、`yumeguri-tfstate-staging` を `yumeguri-tfstate-production` に読みかえて行う。

### バケットを消したいとき

`main.tf` の `prevent_destroy = true` が、消すのを止める。中に入っている state も全部なくなるので、先にすべての環境を `destroy` してから、この行を外して行う。

## イメージを ECR に押し上げる（S1-17 で自動にするまでの、手での手順）

`envs/staging` は、ECR の住所を `envs/staging-persistent` の出力から読む。**先に `staging-persistent` を apply** してから行う。

```bash
export AWS_PROFILE=yumeguri
REG=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-1.amazonaws.com
TAG=$(git rev-parse --short=12 HEAD)   # タグ＝Git のコミット ID（同じタグは上書きできない）
aws ecr get-login-password | docker login --username AWS --password-stdin "$REG"

# --provenance=false --sbom=false：作り方の記録を、タグのない別のイメージとして押し上げない
# （ECR の「タグのないイメージは1日で消す」ルールで、イメージが壊れないように）
docker buildx build --platform linux/arm64 --provenance=false --sbom=false \
  -t "$REG/yumeguri-api:$TAG" -f apps/api/Dockerfile --push .
docker buildx build --platform linux/arm64 --provenance=false --sbom=false \
  -t "$REG/yumeguri-worker:$TAG" -f services/worker/Dockerfile --push services/worker
```

そのあと、`envs/staging/terraform.tfvars` の `image_tag` を、このタグにして apply する。

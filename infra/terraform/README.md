# infra/terraform

AWS に作るもの（staging・production の環境）を、コードで書いておく場所。

```
infra/terraform/
├── bootstrap/      # 最初に1回だけ作るもの：state を置く S3 のバケット
├── modules/        # staging・production で同じものを作るための部品（S1-13 から）
└── envs/
    └── staging/    # staging の環境。state は bootstrap のバケットに置く
```

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

各フォルダの `terraform.tfvars.example` を `terraform.tfvars` にコピーして、アカウント ID を入れる。`terraform.tfvars` は Git に入らない。ほかのアカウントにつながっていると、`plan` の時点で止まる（`allowed_account_ids`）。

## ふだんの使い方（envs/staging）

```bash
cd infra/terraform/envs/staging
terraform init     # 最初の1回と、プロバイダーの版を変えたとき
terraform plan     # 何が変わるかを読む。destroy・replace があれば、理由が分かるまで apply しない
terraform apply
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

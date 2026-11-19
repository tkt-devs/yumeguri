variable "name" {
  description = "使うときだけの層の名前（例：yumeguri-staging）。消してよいリソースの名前の頭"
  type        = string
}

variable "oidc_provider_arn" {
  description = "GitHub の OIDC のプロバイダー（modules/github_deploy が作る。アカウントに1つだけ）"
  type        = string
}

variable "allowed_subjects" {
  description = "ロールを引き受けてよい GitHub の身分証の sub（例：repo:<owner>@<id>/<repo>@<id>:environment:staging-reaper）"
  type        = list(string)
}

variable "secret_prefix" {
  description = "使うときだけの層のシークレットの名前の頭（例：yumeguri/staging）"
  type        = string
}

variable "state_bucket" {
  description = "terraform の state のバケット"
  type        = string
}

variable "state_key" {
  description = "使うときだけの層の state の場所（読み書きする）"
  type        = string
}

variable "persistent_state_key" {
  description = "ずっと残す層の state の場所（読むだけ。terraform_remote_state で読む）"
  type        = string
}

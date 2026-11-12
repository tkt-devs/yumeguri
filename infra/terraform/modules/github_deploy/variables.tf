variable "name" {
  description = "デプロイ先の環境の名前（例：yumeguri-staging）。ECS のクラスターの名前で、ロール・タスク定義・ロググループの名前の頭"
  type        = string
}

variable "allowed_subjects" {
  description = "ロールを引き受けてよい GitHub の身分証の sub（例：repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main）"
  type        = list(string)
}

variable "ecr_repository_arns" {
  description = "イメージを押し上げてよい ECR のリポジトリ"
  type        = list(string)
}

variable "image_tag_parameter_arn" {
  description = "staging に出すイメージのタグを入れておく SSM のパラメータ"
  type        = string
}

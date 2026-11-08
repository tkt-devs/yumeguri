variable "prefix" {
  description = "シークレットの名前の頭（例：yumeguri/staging）"
  type        = string
}

variable "secrets" {
  description = "作る入れ物：名前 → 説明。値は Terraform に書かず、作った後に CLI か管理画面で入れる"
  type        = map(string)
}

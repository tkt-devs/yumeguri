variable "env" {
  description = "環境の名前（staging・production）。バケットの名前とタグに使う"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.env)
    error_message = "env は staging か production にする。"
  }
}

variable "account_id" {
  description = "操作してよい AWS のアカウント ID。プロファイルを取り違えたとき、ほかのアカウントを操作しないための鍵"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id は 12 桁の数字にする。"
  }
}

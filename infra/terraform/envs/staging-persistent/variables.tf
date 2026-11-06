variable "account_id" {
  description = "staging の AWS のアカウント ID。プロファイルを取り違えたとき、ほかのアカウントを操作しないための鍵"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id は 12 桁の数字にする。"
  }
}

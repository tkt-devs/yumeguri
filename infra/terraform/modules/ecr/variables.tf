variable "repositories" {
  description = "作るリポジトリの名前（例：yumeguri-api）"
  type        = set(string)
}

variable "keep_images" {
  description = "タグの付いたイメージを、新しいほうから何個残すか"
  type        = number
  default     = 10
}

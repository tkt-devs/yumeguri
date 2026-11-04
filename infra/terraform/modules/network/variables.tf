variable "name" {
  description = "作るものの名前の頭に付ける文字（例：yumeguri-staging）"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の IP アドレスの範囲"
  type        = string
}

variable "azs" {
  description = "使う AZ（2つ）。1つ目に NAT の EC2 を置く"
  type        = list(string)

  validation {
    condition     = length(var.azs) == 2
    error_message = "azs は 2 つにする（AWS 構成図 v0.1）。"
  }
}

variable "public_subnet_cidrs" {
  description = "公開のサブネットの IP アドレスの範囲（azs と同じ順番・同じ数。数が違うと plan で止まる）"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "非公開のサブネットの IP アドレスの範囲（azs と同じ順番・同じ数。数が違うと plan で止まる）"
  type        = list(string)
}

variable "nat_instance_type" {
  description = "NAT の代わりの EC2 の種類（ADR-013）。AMI が ARM 用なので、ARM（g の付く種類）にする"
  type        = string
  default     = "t4g.nano"
}

variable "app_port" {
  description = "API のコンテナが待ち受けるポート（ALB → API）"
  type        = number
  default     = 3001
}

variable "alb_ingress_cidrs" {
  description = "ALB の 443 に届いてよい IP アドレスの範囲（Cloudflare の IPv4 の範囲を渡す。ADR-013）"
  type        = list(string)

  validation {
    condition     = length(var.alb_ingress_cidrs) > 0
    error_message = "alb_ingress_cidrs が空だと、ALB に誰も届かない。"
  }
}

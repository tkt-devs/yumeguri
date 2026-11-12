# 部品（module）では、版を「この版以上」とだけ書く。ちょうどの版は、使う側（envs/）で固定する
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.70.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.28.1"
    }
  }
}

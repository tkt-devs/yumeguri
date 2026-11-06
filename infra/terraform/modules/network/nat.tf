# NAT の代わりの小さな EC2（ADR-013）
# 非公開のサブネットのタスクが外（Google・Sentry・AWS の API）へ出るとき、ここを中継する
# - 公開のサブネット（1つ目の AZ）に1台。公開の IP を付ける
# - 送信元／送信先のチェックを無効にする（自分宛てではない通信を中継するため）
# - 中に入るときは Session Manager。SSH の鍵も 22 番のポートも使わない

# Amazon Linux 2023（ARM 用）の最新の AMI の ID。AWS が SSM のパラメーターに置いている
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[var.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  associate_public_ip_address = true
  source_dest_check           = false
  iam_instance_profile        = aws_iam_instance_profile.nat.name

  # 起動時に1回だけ実行する設定（NAT にする）。変えたら、EC2 を作り直す
  user_data                   = file("${path.module}/nat-user-data.sh")
  user_data_replace_on_change = true

  # IMDSv2 だけを使う（EC2 の中から、ロールの一時的な鍵を盗まれにくくする）
  metadata_options {
    http_tokens = "required"
  }

  # CPU のクレジット：unlimited（t4g の初めの設定と同じ）
  # standard にすると、作った直後はクレジットが 0 なので、CPU が 5% に抑えられ、最初の設定（dnf）が終わらない
  # （2026-11-04 の apply で実際に起きた）。ふだんの NAT は CPU をほとんど使わないので、追加の料金はほぼかからない
  credit_specification {
    cpu_credits = "unlimited"
  }

  root_block_device {
    encrypted = true
  }

  tags = { Name = "${var.name}-nat" }

  lifecycle {
    # AWS が新しい AMI を出すたびに、plan で「作り直し」にならないようにする
    # （down → up で作り直すときに、そのときの最新の AMI になる）
    ignore_changes = [ami]
  }
}

# 非公開のサブネットから外（0.0.0.0/0）へは、NAT の EC2 を通る
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# ---- NAT の EC2 のロール（Session Manager で中に入るためだけ） ----

data "aws_iam_policy_document" "nat_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nat" {
  name               = "${var.name}-nat"
  assume_role_policy = data.aws_iam_policy_document.nat_assume.json
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  name = "${var.name}-nat"
  role = aws_iam_role.nat.name
}

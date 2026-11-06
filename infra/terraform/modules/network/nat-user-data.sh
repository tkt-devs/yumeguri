#!/bin/bash
# NAT の EC2 が最初に起動したときに1回だけ実行される（Amazon Linux 2023）
# AWS の公式の手順（VPC のユーザーガイド「NAT インスタンス」）と同じ内容
set -euo pipefail

# OS の更新は、ここではしない。使うたびに作り直す（down → up）ので、そのときの最新の AMI になる

# 0. t4g.nano はメモリが 0.5GB しかなく、dnf がメモリ不足で止められる（2026-11-04 の apply で実際に起きた）
#    dnf を使う間だけ、ディスクに 1GB の swap（メモリの代わりの場所）を作る
dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# 1. 再起動しても消えない iptables（通信の書き換えのルール）を使えるようにする
#    この設定は1回しか実行されないので、起動の直後でネットワークが不安定なときに備えて、5回まで試す
for i in 1 2 3 4 5; do
  dnf install -y iptables-services && break
  [ "$i" = 5 ] && exit 1
  sleep 10
done
swapoff /swapfile
rm -f /swapfile
systemctl enable --now iptables

# 2. 自分宛てではない通信を、ほかへ転送できるようにする
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/custom-ip-forwarding.conf
sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf

# 3. 中継する通信の送り元を、この EC2 の IP に書き換える（MASQUERADE）
#    ネットワークの差し込み口の名前（ens5 など）は、種類によって変わるので調べる
iface="$(ip route show default | awk '{print $5; exit}')"
iptables -t nat -A POSTROUTING -o "$iface" -j MASQUERADE
# iptables-services の初めのルールは、転送を全部断る。それを消す（何を通すかはセキュリティグループで決める）
iptables -F FORWARD
service iptables save

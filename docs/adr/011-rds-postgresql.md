# ADR-011: DB は RDS for PostgreSQL にする

- 状態：決定
- 日付：2026-10-30

## 背景

DB に PostgreSQL を使う。AWS で PostgreSQL を動かす方法を決める。

## 選択肢

| 選択肢 | 良いところ | 悪いところ |
| --- | --- | --- |
| RDS for PostgreSQL | 一番小さいサイズ（`db.t4g.micro`）なら安い。自動のバックアップ、指定した時刻への復元（PITR）がある。SAA の基本の形 | 容量や性能の自動の調整は、Aurora ほどではない |
| Aurora PostgreSQL（Serverless v2 を含む） | 性能と可用性が高い。Serverless v2 は、使っていないときに小さくなる | 料金の仕組みが複雑で、見積もりがしにくい。小さく使うには割高になりやすい |
| Supabase | すぐに使える。管理の画面が便利 | AWS の学習にならない。VPC の中に置けない |

## 決めたこと

**RDS for PostgreSQL 18**（`db.t4g.micro`・gp3 20GB・Single-AZ）にする。Single-AZ にした理由は ADR-019。

## 理由

- S0-11 の見積もりで、月 約21ドル（24時間動かした場合）と、予算に収まることを確かめた
- PostgreSQL 18 は、RDS で使える最新のメジャーバージョン（2031年2月まで標準のサポート）
- RDS の構成（サブネットグループ・セキュリティグループ・スナップショット）は、SAA の基本そのもの

## 捨てた選択肢

- **Aurora**：小さく使うには割高で、見積もりもしにくいので採らない
- **Supabase**：AWS の学習にならないので採らない

## リスクと、その対策

- ローカルの Docker の PostgreSQL も 18 にそろえる。`postgres:18` のイメージは、データを置く場所が `/var/lib/postgresql` に変わったので、ボリュームの付け方に気をつける（S1-04）
- DB の接続の数が足りなくなったら、RDS Proxy を検討する（負荷試験の結果で決める）

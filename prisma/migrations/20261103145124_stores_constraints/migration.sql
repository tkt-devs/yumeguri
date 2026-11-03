-- Prisma のスキーマでは書けない制約と権限（docs/erd.md の [SQL] の印のもの）

-- BusinessHour：曜日は 0（日）〜6（土）
ALTER TABLE "BusinessHour"
  ADD CONSTRAINT "BusinessHour_weekday_check" CHECK ("weekday" BETWEEN 0 AND 6);

-- BusinessHour：開く時刻と閉じる時刻が同じ行を作らせない（閉じる時刻が小さければ、日付をまたぐ営業）
ALTER TABLE "BusinessHour"
  ADD CONSTRAINT "BusinessHour_opens_closes_check" CHECK ("opens_at" <> "closes_at");

-- Photo：「準備完了なのにサムネイルがない」行を作らせない
ALTER TABLE "Photo"
  ADD CONSTRAINT "Photo_ready_has_thumbnail_check" CHECK ("status" <> 'ready' OR "thumbnail_key" IS NOT NULL);

-- Photo：ワーカーは写真の加工の結果（状態・サムネイル・大きさ）を読み書きするだけ（ADR-005）
-- 写真の行を作る・消すのは API（yumeguri_app）
GRANT SELECT, UPDATE ON "Photo" TO yumeguri_worker;

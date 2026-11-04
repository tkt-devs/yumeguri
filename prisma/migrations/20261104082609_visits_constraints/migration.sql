-- Prisma のスキーマでは書けない制約（docs/erd.md の [SQL] の印のもの）

-- Visit：同じ人が、同じ日に、同じ銭湯に2回チェックインできない（要件定義書 9.4）
-- 取り消した来訪（revoked_at が入っている行）は数えないので、取り消したあとにもう一度チェックインできる
-- 同時に2つのリクエストが来ても、片方はこの一意の制約で断られる（アプリで先に調べる方法では防げない）
CREATE UNIQUE INDEX "Visit_user_id_store_id_visited_on_active_key"
  ON "Visit" ("user_id", "store_id", "visited_on")
  WHERE "revoked_at" IS NULL;

-- Visit：手動で付けた来訪には、付けたスタッフが必ず残る
ALTER TABLE "Visit"
  ADD CONSTRAINT "Visit_manual_has_created_by_check" CHECK ("source" <> 'manual' OR "created_by" IS NOT NULL);

-- Prisma のスキーマでは書けない部分インデックス（docs/erd.md の [SQL] の印のもの）

-- Store：公開の一覧（公開中で消されていない銭湯を、名前 → id の順に並べて、カーソルの続きから取る）を速くする
CREATE INDEX "Store_public_name_id_idx"
  ON "Store" ("name", "id")
  WHERE "status" = 'published' AND "deleted_at" IS NULL;

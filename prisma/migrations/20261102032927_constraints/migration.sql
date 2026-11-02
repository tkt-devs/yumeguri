-- Prisma のスキーマでは書けない制約と権限（docs/erd.md の [SQL] の印のもの）

-- Membership：団体の管理者（store_id が NULL）も、同じ役割を2回持てないようにする
-- 普通の一意の制約は NULL どうしを「別の値」とみなすので、NULLS NOT DISTINCT 付きで作り直す
DROP INDEX "Membership_user_id_organization_id_store_id_role_key";
CREATE UNIQUE INDEX "Membership_user_id_organization_id_store_id_role_key"
  ON "Membership" ("user_id", "organization_id", "store_id", "role") NULLS NOT DISTINCT;

-- Membership：団体の管理者には銭湯がなく、スタッフ・オーナーには必ず銭湯がある
ALTER TABLE "Membership"
  ADD CONSTRAINT "Membership_store_matches_role_check"
  CHECK (("role" = 'org_admin') = ("store_id" IS NULL));

-- AuditLog：追記だけにする。アプリ用の DB ユーザーは、書き換えも削除もできない（FR-ADM-02）
REVOKE UPDATE, DELETE ON "AuditLog" FROM yumeguri_app;

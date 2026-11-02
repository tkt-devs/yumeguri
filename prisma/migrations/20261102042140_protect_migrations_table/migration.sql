-- マイグレーションの記録（_prisma_migrations）は、アプリ用・ワーカー用の DB ユーザーから触らせない
-- （ALTER DEFAULT PRIVILEGES で、ほかの表と一緒に読み書きの権限が付いてしまうため）
-- シャドウ DB にはこの表がないので、あるときだけ取り上げる
DO $$
BEGIN
  IF to_regclass('public._prisma_migrations') IS NOT NULL THEN
    REVOKE ALL ON "_prisma_migrations" FROM yumeguri_app, yumeguri_worker;
  END IF;
END
$$;

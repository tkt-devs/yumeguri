-- CreateEnum
CREATE TYPE "VisitSource" AS ENUM ('qr', 'posted_qr', 'manual');

-- CreateTable
CREATE TABLE "Visit" (
    "id" UUID NOT NULL DEFAULT uuidv7(),
    "user_id" UUID NOT NULL,
    "store_id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "visited_on" DATE NOT NULL,
    "source" "VisitSource" NOT NULL,
    "created_by" UUID,
    "revoked_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Visit_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Visit_store_id_visited_on_idx" ON "Visit"("store_id", "visited_on");

-- CreateIndex
CREATE INDEX "Visit_user_id_visited_on_idx" ON "Visit"("user_id", "visited_on");

-- AddForeignKey
ALTER TABLE "Visit" ADD CONSTRAINT "Visit_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Visit" ADD CONSTRAINT "Visit_store_id_organization_id_fkey" FOREIGN KEY ("store_id", "organization_id") REFERENCES "Store"("id", "organization_id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Visit" ADD CONSTRAINT "Visit_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

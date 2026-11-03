-- CreateEnum
CREATE TYPE "StoreStatus" AS ENUM ('draft', 'published', 'closed');

-- CreateEnum
CREATE TYPE "PhotoStatus" AS ENUM ('uploading', 'processing', 'ready', 'failed');

-- CreateTable
CREATE TABLE "Store" (
    "id" UUID NOT NULL DEFAULT uuidv7(),
    "organization_id" UUID NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "name_kana" TEXT,
    "description" TEXT,
    "prices" JSONB,
    "status" "StoreStatus" NOT NULL DEFAULT 'draft',
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Store_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BusinessHour" (
    "id" UUID NOT NULL DEFAULT uuidv7(),
    "store_id" UUID NOT NULL,
    "weekday" SMALLINT NOT NULL,
    "opens_at" TIME(0) NOT NULL,
    "closes_at" TIME(0) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BusinessHour_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Photo" (
    "id" UUID NOT NULL DEFAULT uuidv7(),
    "store_id" UUID NOT NULL,
    "original_key" TEXT NOT NULL,
    "thumbnail_key" TEXT,
    "status" "PhotoStatus" NOT NULL DEFAULT 'uploading',
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "width" INTEGER,
    "height" INTEGER,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Photo_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Store_slug_key" ON "Store"("slug");

-- CreateIndex
CREATE INDEX "Store_organization_id_status_idx" ON "Store"("organization_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "Store_id_organization_id_key" ON "Store"("id", "organization_id");

-- CreateIndex
CREATE INDEX "BusinessHour_store_id_weekday_idx" ON "BusinessHour"("store_id", "weekday");

-- CreateIndex
CREATE INDEX "Photo_store_id_sort_order_idx" ON "Photo"("store_id", "sort_order");

-- AddForeignKey
ALTER TABLE "Membership" ADD CONSTRAINT "Membership_store_id_organization_id_fkey" FOREIGN KEY ("store_id", "organization_id") REFERENCES "Store"("id", "organization_id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Store" ADD CONSTRAINT "Store_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BusinessHour" ADD CONSTRAINT "BusinessHour_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Photo" ADD CONSTRAINT "Photo_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

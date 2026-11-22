import type { StoreDetailResponse, StoreListItemResponse } from '@yumeguri/shared';

// Repository が Service に渡す形。Prisma のモデルを外に漏らさないためのもの
// レスポンスの形から作り、違いは「画像の URL の代わりに S3 のキーを持つ」ことだけにする

// 一覧の1行。写真がなければ thumbnailKey は null
export type PublishedStoreSummary = Omit<StoreListItemResponse, 'thumbnailUrl'> & {
  thumbnailKey: string | null;
};

// 一覧の「ここより後ろ」の位置。名前が同じ銭湯があっても順番が決まるように、id も持つ
export type StoreListPosition = Pick<StoreListItemResponse, 'name' | 'id'>;

export type PublicStoreDetail = Omit<StoreDetailResponse, 'photos'> & {
  photos: (Omit<StoreDetailResponse['photos'][number], 'url'> & { thumbnailKey: string })[];
};

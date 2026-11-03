import 'dotenv/config';
import { createPrismaClient } from '../apps/api/src/repositories/prismaClient';
import { toDbTime } from '../apps/api/src/utils/dbTime';

// 開発用の架空のデータ。何回実行しても同じ結果になるように、ID を決めて upsert する
const url = process.env['MIGRATE_DATABASE_URL'];
if (!url) {
  throw new Error('MIGRATE_DATABASE_URL を .env に書いてください');
}
const prisma = createPrismaClient(url);

// 決まった ID（UUID v7 の形）。団体は 1〜、利用者は 101〜、銭湯は 201〜
const fixedId = (n: number) => `019a4000-0000-7000-8000-${String(n).padStart(12, '0')}`;

const ORGANIZATIONS = [
  { id: fixedId(1), name: 'A 浴場組合', slug: 'a-bath-union' },
  { id: fixedId(2), name: 'B 浴場組合', slug: 'b-bath-union' },
  { id: fixedId(3), name: 'C 浴場組合', slug: 'c-bath-union' },
];
const PLATFORM_ADMIN_ID = fixedId(101);

for (const org of ORGANIZATIONS) {
  await prisma.organization.upsert({ where: { id: org.id }, update: org, create: org });
}

await prisma.user.upsert({
  where: { id: PLATFORM_ADMIN_ID },
  update: {},
  create: {
    id: PLATFORM_ADMIN_ID,
    displayName: 'システム管理者',
    email: 'admin@example.com',
    platformRoles: { create: { role: 'platform_admin' } },
  },
});

// 営業時間の型。closes が opens より小さいときは、日付をまたぐ営業（例：15:00〜翌1:00）
type WeeklyHours = {
  // 定休日の曜日（0：日〜6：土）
  closedDays: number[];
  // 営業する曜日は、どれも同じ時間帯。1日に2つの時間帯も持てる
  slots: { opens: string; closes: string }[];
};

// 営業時間の型の見本（権限・表示のテストで使い分ける）
const HOURS = {
  // 15:00〜23:00、月曜が定休日
  standard: { closedDays: [1], slots: [{ opens: '15:00', closes: '23:00' }] },
  // 15:00〜翌1:00（日付をまたぐ）、水曜が定休日
  lateNight: { closedDays: [3], slots: [{ opens: '15:00', closes: '01:00' }] },
  // 朝湯（6:00〜9:00）と、夕方からの営業（15:00〜24:00）。火曜が定休日
  morningAndEvening: {
    closedDays: [2],
    slots: [
      { opens: '06:00', closes: '09:00' },
      { opens: '15:00', closes: '00:00' },
    ],
  },
  // 定休日なし
  noHoliday: { closedDays: [], slots: [{ opens: '14:00', closes: '23:30' }] },
  // 閉店（営業時間なし）
  none: { closedDays: [0, 1, 2, 3, 4, 5, 6], slots: [] },
} satisfies Record<string, WeeklyHours>;

const PRICES = { adult: 520, child: 200, infant: 100 };

// 架空の銭湯10軒。code の1文字目が団体（A・B・C）。権限のテストで「他の団体の銭湯」を作るため
// 実在の銭湯とぶつからないように、名前は「A1 の湯」の形にする
const STORES = [
  { code: 'A1', status: 'published', hours: HOURS.standard },
  { code: 'A2', status: 'published', hours: HOURS.lateNight },
  { code: 'A3', status: 'published', hours: HOURS.morningAndEvening },
  { code: 'A4', status: 'draft', hours: HOURS.standard },
  { code: 'B1', status: 'published', hours: HOURS.noHoliday },
  { code: 'B2', status: 'published', hours: HOURS.lateNight },
  { code: 'B3', status: 'closed', hours: HOURS.none },
  { code: 'C1', status: 'published', hours: HOURS.standard },
  { code: 'C2', status: 'published', hours: HOURS.morningAndEvening },
  { code: 'C3', status: 'published', hours: HOURS.noHoliday },
] as const;

for (const [index, { code, status, hours }] of STORES.entries()) {
  const id = fixedId(201 + index);
  const organization = ORGANIZATIONS['ABC'.indexOf(code[0] ?? '')];
  if (!organization) throw new Error(`${code} の団体がない`);
  const name = `${code} の湯`;
  const data = {
    organizationId: organization.id,
    slug: `${code.toLowerCase()}-no-yu`,
    name,
    description: `${name}は、開発用の架空の銭湯です。`,
    prices: PRICES,
    status,
  };
  // 「定休日なし」の [] も含めて、数の配列として扱う
  const closedDays: readonly number[] = hours.closedDays;
  const businessHours = [0, 1, 2, 3, 4, 5, 6]
    .filter((weekday) => !closedDays.includes(weekday))
    .flatMap((weekday) =>
      hours.slots.map((slot) => ({
        storeId: id,
        weekday,
        opensAt: toDbTime(slot.opens),
        closesAt: toDbTime(slot.closes),
      })),
    );

  // 営業時間は、いったん消して入れ直す（何回実行しても同じ行になる）
  await prisma.$transaction([
    prisma.store.upsert({ where: { id }, update: data, create: { id, ...data } }),
    prisma.businessHour.deleteMany({ where: { storeId: id } }),
    ...(businessHours.length > 0 ? [prisma.businessHour.createMany({ data: businessHours })] : []),
  ]);
}

await prisma.$disconnect();

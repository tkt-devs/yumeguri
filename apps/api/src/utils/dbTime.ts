import { TimeOfDay } from '@yumeguri/shared';

// DB の time の列（BusinessHour の opens_at・closes_at）に入れる値を作る
// Prisma は time の列も Date で受け取り、UTC の時刻の部分だけを使う。
// 末尾の Z（UTC）を付けないと、サーバーの時差（JST なら9時間）だけずれる
export function toDbTime(hhmm: string): Date {
  if (!TimeOfDay.safeParse(hhmm).success) {
    throw new Error(`時刻は HH:MM（00:00〜23:59）で書く：${hhmm}`);
  }
  return new Date(`1970-01-01T${hhmm}:00Z`);
}

// DB の time の列から読んだ値を、HH:MM に戻す（UTC の時刻の部分だけを使う）
export function fromDbTime(value: Date): string {
  return value.toISOString().slice(11, 16);
}

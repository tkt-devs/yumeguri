import { describe, expect, it } from 'vitest';
import { toDbTime } from './dbTime';

describe('toDbTime', () => {
  it('HH:MM を、UTC のその時刻の Date にする', () => {
    expect(toDbTime('15:00').toISOString()).toBe('1970-01-01T15:00:00.000Z');
    expect(toDbTime('00:00').toISOString()).toBe('1970-01-01T00:00:00.000Z');
    expect(toDbTime('23:59').toISOString()).toBe('1970-01-01T23:59:00.000Z');
  });

  it.each(['24:00', '9:00', '15:60', '15:00:00', ''])('形の違う値（%s）はエラー', (value) => {
    expect(() => toDbTime(value)).toThrow();
  });
});

import type { ErrorEvent } from '@sentry/node';
import { describe, expect, it } from 'vitest';
import { scrubEvent } from './sentry';

describe('scrubEvent', () => {
  it('例外のメッセージとパンくずを消し、種類とスタックは残す', () => {
    const event = {
      type: undefined,
      exception: {
        values: [
          {
            type: 'Error',
            value: 'connect failed postgresql://app:secret@db:5432/yumeguri',
            stacktrace: { frames: [{ filename: 'index.js', lineno: 1 }] },
          },
        ],
      },
      breadcrumbs: [{ message: 'password=secret' }],
    } satisfies ErrorEvent;

    const scrubbed = scrubEvent(event);

    expect(scrubbed.exception?.values?.[0]?.type).toBe('Error');
    expect(scrubbed.exception?.values?.[0]?.value).toBe('[消した]');
    expect(scrubbed.exception?.values?.[0]?.stacktrace?.frames).toHaveLength(1);
    expect(scrubbed.breadcrumbs).toBeUndefined();
    expect(JSON.stringify(scrubbed)).not.toContain('secret');
  });
});

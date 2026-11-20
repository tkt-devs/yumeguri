import type { ErrorEvent } from '@sentry/nextjs';
import { describe, expect, it } from 'vitest';
import { scrubEvent } from './sentryScrub';

describe('scrubEvent', () => {
  it('例外のメッセージとパンくずを消し、種類とスタックは残す', () => {
    const event = {
      type: undefined,
      exception: {
        values: [
          {
            type: 'TypeError',
            value: 'token=secret',
            stacktrace: { frames: [{ filename: 'page.js', lineno: 1 }] },
          },
        ],
      },
      breadcrumbs: [{ message: 'email=a@example.com' }],
    } satisfies ErrorEvent;

    const scrubbed = scrubEvent(event);

    expect(scrubbed.exception?.values?.[0]?.type).toBe('TypeError');
    expect(scrubbed.exception?.values?.[0]?.value).toBe('[消した]');
    expect(scrubbed.breadcrumbs).toBeUndefined();
    expect(JSON.stringify(scrubbed)).not.toContain('secret');
  });
});

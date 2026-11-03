import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { buildCeleryMessage, CELERY_CORRELATION_ID_HEADER } from './celeryMessage';

const fromBase64Json = (value: string): unknown =>
  JSON.parse(Buffer.from(value, 'base64').toString('utf8'));

describe('buildCeleryMessage', () => {
  const message = buildCeleryMessage({
    taskId: 'task-1',
    task: 'debug.add',
    kwargs: { x: 2, y: 3 },
    queue: 'jobs-heavy',
    correlationId: 'cid-1',
    deliveryTag: 'tag-1',
  });

  it('Celery の封筒に、タスクの名前・ID・相関 ID・送り先のキューが入る', () => {
    expect(fromBase64Json(message)).toMatchObject({
      'content-type': 'application/json',
      headers: {
        task: 'debug.add',
        id: 'task-1',
        root_id: 'task-1',
        [CELERY_CORRELATION_ID_HEADER]: 'cid-1',
      },
      properties: {
        body_encoding: 'base64',
        delivery_info: { routing_key: 'jobs-heavy' },
        delivery_tag: 'tag-1',
      },
    });
  });

  it('body は [位置の引数, 名前つきの引数, つなげるタスク] を base64 にしたもの', () => {
    const envelope = fromBase64Json(message);
    if (typeof envelope !== 'object' || envelope === null || !('body' in envelope)) {
      throw new Error('body がない');
    }
    if (typeof envelope.body !== 'string') throw new Error('body が文字列ではない');

    expect(fromBase64Json(envelope.body)).toEqual([
      [],
      { x: 2, y: 3 },
      { callbacks: null, errbacks: null, chain: null, chord: null },
    ]);
  });
});

// ワーカー（Python）との約束のテスト。同じファイルを、ワーカーの tests/test_api_message_contract.py が
// Celery で読めることを確かめている。メッセージの形を変えたら、このファイルも作り直す
// （作り直し方：このテストが失敗したときに表示される、新しい値（Received）を、そのファイルに貼る）
describe('ワーカーとの約束（services/worker/tests/fixtures/celery-message-debug-add.txt）', () => {
  it('決まった値で作ったメッセージが、ファイルの中身と同じになる', () => {
    const fixture = readFileSync(
      new URL(
        '../../../../services/worker/tests/fixtures/celery-message-debug-add.txt',
        import.meta.url,
      ),
      'utf8',
    ).trim();

    expect(
      buildCeleryMessage({
        taskId: '00000000-0000-4000-8000-000000000001',
        task: 'debug.add',
        kwargs: { x: 2, y: 3 },
        queue: 'jobs-default',
        correlationId: '00000000-0000-4000-8000-000000000002',
        deliveryTag: '00000000-0000-4000-8000-000000000003',
      }),
    ).toBe(fixture);
  });
});

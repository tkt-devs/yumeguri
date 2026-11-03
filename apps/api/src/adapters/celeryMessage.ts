import type { JobQueueName, JsonValue } from './jobQueue';

// ワーカーが相関 ID を読むメッセージのヘッダーの名前（services/worker の app/celery_app.py と同じ）
export const CELERY_CORRELATION_ID_HEADER = 'correlationId';

type CeleryMessageInput = {
  taskId: string;
  task: string;
  kwargs: Record<string, JsonValue>;
  queue: JobQueueName;
  correlationId: string;
  deliveryTag: string;
};

const toBase64Json = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64');

// Celery（kombu の SQS）が読める形の、SQS のメッセージの本文を作る
// Celery のメッセージの形（protocol 2）：https://docs.celeryq.dev/en/stable/internals/protocol.html
// 外側の封筒（headers・properties）の中に、タスクの引数を base64 にした body が入り、封筒ごと base64 にして送る
export function buildCeleryMessage(input: CeleryMessageInput): string {
  const { taskId, task, kwargs, queue, correlationId, deliveryTag } = input;
  return toBase64Json({
    // [位置の引数, 名前つきの引数, つなげるタスク]。このアプリは名前つきの引数だけを使う
    body: toBase64Json([[], kwargs, { callbacks: null, errbacks: null, chain: null, chord: null }]),
    'content-encoding': 'utf-8',
    'content-type': 'application/json',
    headers: {
      lang: 'py',
      task,
      id: taskId,
      root_id: taskId,
      parent_id: null,
      group: null,
      retries: 0,
      eta: null,
      expires: null,
      timelimit: [null, null],
      // ワーカーのログ（受け取った・成功した）に出す、引数の表し方
      argsrepr: '()',
      kwargsrepr: JSON.stringify(kwargs),
      origin: 'yumeguri-api',
      [CELERY_CORRELATION_ID_HEADER]: correlationId,
    },
    properties: {
      correlation_id: taskId,
      delivery_mode: 2,
      // kombu は routing_key でキューを選ぶ
      delivery_info: { exchange: '', routing_key: queue },
      priority: 0,
      body_encoding: 'base64',
      delivery_tag: deliveryTag,
    },
  });
}

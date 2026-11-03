// 確認用：API の部品（SqsJobQueue）で、ワーカーの debug.add をキューに入れる（S1-09）
// 使い方：pnpm --filter @yumeguri/api enqueue:debug-add 2 3
// 本物のジョブ（写真の加工など）ができたら、このファイルを消す
import { randomUUID } from 'node:crypto';
import { SQSClient } from '@aws-sdk/client-sqs';
import { z } from 'zod';
import { SqsJobQueue } from '../src/adapters/sqsJobQueue';
import { loadEnv } from '../src/config/env';
import { createLogger } from '../src/logger';

const Args = z.tuple([z.coerce.number().int(), z.coerce.number().int()]);

const env = loadEnv();
const logger = createLogger(env.LOG_LEVEL);
const [x, y] = Args.parse(process.argv.slice(2));

const queue = new SqsJobQueue(new SQSClient({}), {
  'jobs-default': env.SQS_QUEUE_URL_DEFAULT,
  'jobs-heavy': env.SQS_QUEUE_URL_HEAVY,
});
const correlationId = randomUUID();
const taskId = await queue.enqueue({
  task: 'debug.add',
  kwargs: { x, y },
  queue: 'jobs-default',
  correlationId,
});
logger.info({ correlationId, taskId, task: 'debug.add' }, 'job enqueued');

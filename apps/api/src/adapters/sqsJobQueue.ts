import { randomUUID } from 'node:crypto';
import { SendMessageCommand, type SQSClient } from '@aws-sdk/client-sqs';
import { buildCeleryMessage } from './celeryMessage';
import type { EnqueueJob, JobQueue, JobQueueName } from './jobQueue';

// SQS に、Celery のワーカーが読める形のメッセージを送る
export class SqsJobQueue implements JobQueue {
  constructor(
    private readonly sqs: SQSClient,
    // キューの URL（Terraform・LocalStack の init のスクリプトが作る）。キューの名前から引く
    private readonly queueUrls: Readonly<Record<JobQueueName, string>>,
  ) {}

  async enqueue(job: EnqueueJob): Promise<string> {
    const taskId = randomUUID();
    await this.sqs.send(
      new SendMessageCommand({
        QueueUrl: this.queueUrls[job.queue],
        MessageBody: buildCeleryMessage({ ...job, taskId, deliveryTag: randomUUID() }),
      }),
    );
    return taskId;
  }
}

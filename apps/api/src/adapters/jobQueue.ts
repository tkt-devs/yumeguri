// ジョブのキュー（ADR-012）。軽いジョブは jobs-default、重いジョブは jobs-heavy
export type JobQueueName = 'jobs-default' | 'jobs-heavy';

// JSON にそのまま変えられる値（Date・undefined などを渡せないようにする）
export type JsonValue =
  string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

export type EnqueueJob = {
  // ワーカーのタスクの名前（services/worker の @celery_app.task(name=…)）
  task: string;
  // タスクに渡す引数。ID などの小さな値だけ（個人情報・大きなデータは DB・S3 から読む）
  kwargs: Record<string, JsonValue>;
  queue: JobQueueName;
  // ワーカーのログにも同じ相関 ID を付けて、API のリクエストとつなげる
  correlationId: string;
};

export interface JobQueue {
  // キューに入れて、タスクの ID を返す（ワーカーの処理は待たない）
  enqueue(job: EnqueueJob): Promise<string>;
}

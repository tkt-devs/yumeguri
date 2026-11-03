from typing import Any

from celery import Celery, Task
from celery.signals import setup_logging, task_postrun, task_prerun
from kombu import Queue

from app.config import Settings, load_settings
from app.logs import configure_logging, correlation_id_var

# キューの名前（ADR-012）。軽いジョブは default、重いジョブは heavy
QUEUE_DEFAULT = "jobs-default"
QUEUE_HEAVY = "jobs-heavy"

# ジョブの実行時間の上限（要件定義書 11.2）
# ソフトの上限で後片付けをしてから止まり、ハードの上限で強制的に止まる
# 重いジョブは、ジョブごとにもっと長い上限を付ける（S3-01）
# どちらも、そのキューの可視性タイムアウト（docker/localstack/init/01-resources.sh）より短くする
DEFAULT_SOFT_TIME_LIMIT_SECONDS = 50
DEFAULT_TIME_LIMIT_SECONDS = 60

# API から受け取る、相関 ID のメッセージのヘッダーの名前
# apps/api の adapters/celeryMessage.ts と同じにする
CORRELATION_ID_HEADER = "correlationId"


def create_celery_app(settings: Settings) -> Celery:
    """SQS をブローカーにした Celery のアプリを作る。

    Args:
        settings: 環境変数から読んだ設定

    Returns:
        設定済みの Celery のアプリ
    """
    # キューの名前と URL の対応。Celery の2つの設定を、ここから作る
    queue_urls = {
        QUEUE_DEFAULT: settings.sqs_queue_url_default,
        QUEUE_HEAVY: settings.sqs_queue_url_heavy,
    }
    celery = Celery("yumeguri_worker")
    celery.conf.update(
        # 接続先を書かない。ローカルは AWS_PROFILE=localstack の endpoint_url で LocalStack に、
        # 本番は ECS のタスクロールで本物の SQS につながる
        broker_url="sqs://",
        broker_transport_options={
            "region": settings.aws_region,
            # 長いポーリング：メッセージがないとき、最大20秒待ってから返す
            # kombu は受け取るたびに自分の値（初期は10秒）を送り、キューの側の設定より優先される
            "wait_time_seconds": 20,
            # キューを Celery に作らせず、探させもしない（本番では Terraform が作る）
            # この設定のときは、可視性タイムアウトを Celery ではなく、SQS のキューの側で決める
            "predefined_queues": {name: {"url": str(url)} for name, url in queue_urls.items()},
        },
        task_queues=[Queue(name, routing_key=name) for name in queue_urls],
        task_default_queue=QUEUE_DEFAULT,
        task_create_missing_queues=False,
        # SQS では、ワーカーへの遠隔の命令（ping など）が使えない。使うとキューを作ろうとする
        worker_enable_remote_control=False,
        task_serializer="json",
        accept_content=["json"],
        # ジョブの状態と結果は、DB の Job の表で管理する（S3-01）。Celery には保存させない
        task_ignore_result=True,
        # 実行が終わってから、SQS のメッセージを消す
        # 途中でワーカーが落ちたら、可視性タイムアウトのあとで別のワーカーに渡る
        # そのため、ジョブは何回実行しても結果が同じになるように書く（要件定義書 11.2）
        task_acks_late=True,
        task_reject_on_worker_lost=True,
        # 失敗・時間切れのときも消さない（初期の Celery は消してしまう）
        # 可視性タイムアウトのあとでもう一度届き、3回で DLQ に移る（SQS の再処理ポリシー）
        # 恒久的な失敗は、タスクの中で Job を「失敗」にして、正常に終わらせる（S3-01）
        task_acks_on_failure_or_timeout=False,
        # 1つずつ受け取る。まとめて受け取ると、待っている間に可視性タイムアウトが過ぎて、
        # 別のワーカーにも渡ってしまう
        worker_prefetch_multiplier=1,
        worker_pool=settings.celery_pool,
        worker_concurrency=settings.celery_concurrency,
        task_soft_time_limit=DEFAULT_SOFT_TIME_LIMIT_SECONDS,
        task_time_limit=DEFAULT_TIME_LIMIT_SECONDS,
        include=["app.tasks.debug"],
    )
    return celery


settings = load_settings()
celery_app = create_celery_app(settings)


# この signal に関数をつなぐと、Celery は自分のログの設定をしない（代わりに JSON のログにする）
@setup_logging.connect
def _configure_logging(**_: Any) -> None:
    configure_logging(settings.log_level)


# Task[...] は型チェックのときだけの書き方なので、文字列にする
# （実行時の Celery の Task は [] を受け付けない）
@task_prerun.connect
def _bind_correlation_id(task: "Task[Any, Any]", **_: Any) -> None:
    # タスクの実行中に出したログすべてに、API から受け取った相関 ID を付ける
    # メッセージのヘッダーは request.headers に入る（SQS から届いたときも、apply() のときも）
    correlation_id_var.set((task.request.headers or {}).get(CORRELATION_ID_HEADER))


@task_postrun.connect
def _clear_correlation_id(**_: Any) -> None:
    correlation_id_var.set(None)

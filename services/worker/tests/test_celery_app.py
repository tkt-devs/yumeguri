import re
from pathlib import Path

from app.celery_app import (
    DEFAULT_SOFT_TIME_LIMIT_SECONDS,
    DEFAULT_TIME_LIMIT_SECONDS,
    QUEUE_DEFAULT,
    QUEUE_HEAVY,
    celery_app,
)

# キューを作るスクリプト（本番では Terraform。S1-12 からはそちらも確かめる）
LOCALSTACK_INIT_SCRIPT = (
    Path(__file__).resolve().parents[3] / "docker/localstack/init/01-resources.sh"
)


def _visibility_timeout_in_init_script(queue: str) -> int:
    match = re.search(rf"\[{queue}\]=(\d+)", LOCALSTACK_INIT_SCRIPT.read_text())
    assert match is not None, f"{queue} の可視性タイムアウトが、init のスクリプトにない"
    return int(match.group(1))


def test_queues_are_predefined_and_never_created() -> None:
    conf = celery_app.conf
    assert set(conf.broker_transport_options["predefined_queues"]) == {QUEUE_DEFAULT, QUEUE_HEAVY}
    assert {q.name for q in conf.task_queues} == {QUEUE_DEFAULT, QUEUE_HEAVY}
    assert conf.task_create_missing_queues is False


def test_time_limits_are_shorter_than_visibility_timeout() -> None:
    # 上限より可視性タイムアウトが短いと、実行中のジョブが別のワーカーにも渡ってしまう
    assert celery_app.conf.task_soft_time_limit == DEFAULT_SOFT_TIME_LIMIT_SECONDS
    assert celery_app.conf.task_time_limit == DEFAULT_TIME_LIMIT_SECONDS
    assert DEFAULT_TIME_LIMIT_SECONDS < _visibility_timeout_in_init_script(QUEUE_DEFAULT)

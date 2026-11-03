import base64
import json
from pathlib import Path

from celery.worker.request import Request
from kombu import Message

from app.celery_app import CORRELATION_ID_HEADER, celery_app
from app.tasks.debug import add

# API（apps/api/src/adapters/celeryMessage.ts）が作った、SQS のメッセージの本文
# API 側のテスト（celeryMessage.test.ts）が、同じ値を作れることを確かめている
FIXTURE = Path(__file__).parent / "fixtures" / "celery-message-debug-add.txt"


def test_celery_can_read_message_built_by_api() -> None:
    # kombu の SQS と同じ順で開く：本文の base64 → 封筒の JSON → 引数の base64
    envelope = json.loads(base64.b64decode(FIXTURE.read_text().strip()))
    message = Message(
        body=base64.b64decode(envelope["body"]).decode(),
        headers=envelope["headers"],
        content_type=envelope["content-type"],
        content_encoding=envelope["content-encoding"],
        properties=envelope["properties"],
    )

    # ワーカーが SQS から受け取ったときと同じ、Celery の Request にする
    request = Request(message, app=celery_app, task=add)

    assert request.task_name == "debug.add"
    assert request.kwargs == {"x": 2, "y": 3}
    assert request.request_dict[CORRELATION_ID_HEADER] == "00000000-0000-4000-8000-000000000002"
    assert envelope["properties"]["delivery_info"]["routing_key"] == "jobs-default"

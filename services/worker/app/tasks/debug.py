import logging

from app.celery_app import celery_app

logger = logging.getLogger(__name__)


# S1-09 の確認用（API → SQS → ワーカーの道がつながっているか）。本物のジョブができたら消す
@celery_app.task(name="debug.add")
def add(x: int, y: int) -> int:
    result = x + y
    logger.info("debug.add", extra={"x": x, "y": y, "result": result})
    return result

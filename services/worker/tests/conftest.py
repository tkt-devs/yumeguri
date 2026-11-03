import os

# app.celery_app は import したときに設定を読むので、その前に、テスト用の値を入れておく
# （キューの URL は形だけ。テストでは SQS につながない）
os.environ.setdefault("SQS_QUEUE_URL_DEFAULT", "http://localhost:4566/000000000000/jobs-default")
os.environ.setdefault("SQS_QUEUE_URL_HEAVY", "http://localhost:4566/000000000000/jobs-heavy")

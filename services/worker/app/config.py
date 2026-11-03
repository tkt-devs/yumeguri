from typing import Literal

from pydantic import HttpUrl
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """ワーカーが読む環境変数。os.environ を読むのは、このクラスだけ。

    ローカルでは `uv run --env-file .env …` で `.env` を環境変数にしてから起動する。
    """

    log_level: Literal["critical", "error", "warning", "info", "debug"] = "info"
    # ワーカーの子プロセスの作り方。本番（Linux）は prefork（時間の上限が効く）
    # Mac では prefork が動かない（子プロセスを spawn で作るため）ので、
    # ローカルの .env で solo にする
    celery_pool: Literal["prefork", "solo"] = "prefork"
    # 内部の API（FastAPI）の待ち受け。ローカルは自分の Mac からだけ
    # コンテナでは 0.0.0.0 にする（S1-10）
    internal_api_host: str = "127.0.0.1"
    internal_api_port: int = 8000
    # SQS は東京リージョン。kombu は指定しないと us-east-1 で署名してしまう
    aws_region: str = "ap-northeast-1"
    # キューは Terraform（ローカルは LocalStack の init のスクリプト）が作る
    # ワーカーは URL を受け取るだけ
    sqs_queue_url_default: HttpUrl
    sqs_queue_url_heavy: HttpUrl


def load_settings() -> Settings:
    # 必須の値は、引数ではなく環境変数から入る
    return Settings()

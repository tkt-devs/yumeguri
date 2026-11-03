import logging
import sys
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

from pythonjsonlogger.json import JsonFormatter

# 今の処理（タスク）の相関 ID。API から受け取った値を入れ、その間に出したログすべてに付ける
correlation_id_var: ContextVar[str | None] = ContextVar("correlation_id", default=None)


class _ApiCompatibleFormatter(JsonFormatter):
    """API（pino）と同じ項目名・値の形で、1行の JSON を作る。

    CloudWatch Logs で、API とワーカーのログを同じ条件（`level = "error"` など）で探せるようにする。
    """

    def add_fields(
        self,
        log_data: dict[str, Any],
        record: logging.LogRecord,
        message_dict: dict[str, Any],
    ) -> None:
        """ログの1行に、決まった項目を足す。

        Args:
            log_data: 書き出す項目（ここに足す）
            record: Python の logging のレコード
            message_dict: ログを出すときに辞書で渡した項目
        """
        super().add_fields(log_data, record, message_dict)
        # pino と同じく、level は小文字の名前、time は ISO 8601（UTC・ミリ秒）
        log_data["level"] = record.levelname.lower()
        log_data["time"] = (
            datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds")
        ).replace("+00:00", "Z")
        log_data["logger"] = record.name
        # uvicorn が足す、端末の色の制御文字つきの同じ文（msg と重なる）
        log_data.pop("color_message", None)
        correlation_id = correlation_id_var.get()
        if correlation_id is not None:
            log_data["correlationId"] = correlation_id


def configure_logging(level: str) -> None:
    """ルートのロガーを、JSON を標準出力に出す設定にする（ECS が CloudWatch Logs に送る）。

    Celery・uvicorn のログも、ルートのロガーを通るので同じ形になる。

    Args:
        level: ログのレベル（"info" など）
    """
    handler = logging.StreamHandler(sys.stdout)
    # message を pino と同じ msg という名前で出す
    handler.setFormatter(_ApiCompatibleFormatter("%(message)s", rename_fields={"message": "msg"}))
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())

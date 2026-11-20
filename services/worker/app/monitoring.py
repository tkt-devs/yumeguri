from typing import Any

import sentry_sdk

from app.config import Settings


def scrub_event(event: Any, _hint: Any) -> Any:
    """Sentry に送る前に、秘密の値や個人情報が入りうるところを消す（ADR-017）。

    例外のメッセージには、接続の文字列などが入ることがある。
    API（apps/api/src/monitoring/sentry.ts）と同じく、エラーの種類とスタック（どこで起きたか）だけを送る。
    タスクの引数（extra の celery-job）とパンくずも送らない。

    Args:
        event: Sentry が送ろうとしているイベント
        _hint: 元の例外などの手がかり（使わない）

    Returns:
        消したあとのイベント
    """
    for exception in event.get("exception", {}).get("values", []):
        exception["value"] = "[消した]"
    event.pop("breadcrumbs", None)
    event.pop("extra", None)
    return event


def init_sentry(settings: Settings) -> None:
    """DSN があれば Sentry を準備する。なければ何もしない（ローカル・テスト）。

    Args:
        settings: 環境変数から読んだ設定
    """
    if not settings.sentry_dsn:
        return
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.sentry_environment,
        release=settings.sentry_release,
        # 利用者の情報・IP などを送らない。スタックの変数の値も送らない（秘密の値が入りうる）
        send_default_pii=False,
        include_local_variables=False,
        # v0.1 はエラーだけ。処理の時間の計測（トレース）は v0.2（ADR-017）
        traces_sample_rate=0,
        before_send=scrub_event,
    )

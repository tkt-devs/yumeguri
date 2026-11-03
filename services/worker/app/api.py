import uvicorn
from fastapi import FastAPI

from app.config import load_settings
from app.logs import configure_logging


def create_api() -> FastAPI:
    # 外に公開しない内部の API なので、API の説明のページ（/docs など）は出さない
    api = FastAPI(title="yumeguri worker", docs_url=None, redoc_url=None, openapi_url=None)

    # ECS のコンテナのヘルスチェック用。プロセスが生きていれば、いつも 200（SQS などは見ない）
    @api.get("/internal/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    return api


api = create_api()


def main() -> None:
    settings = load_settings()
    configure_logging(settings.log_level)
    uvicorn.run(
        api,
        host=settings.internal_api_host,
        port=settings.internal_api_port,
        # uvicorn に独自のログの設定をさせず、ルートのロガー（JSON）に流す
        log_config=None,
        # 1リクエストごとのログは出さない
        # （ヘルスチェックが30秒ごとに来るのと、IP アドレスが入るため）
        access_log=False,
    )


if __name__ == "__main__":
    main()

import json
import logging

import pytest

from app.logs import configure_logging, correlation_id_var


def test_log_line_matches_api_fields(capsys: pytest.CaptureFixture[str]) -> None:
    configure_logging("info")
    token = correlation_id_var.set("cid-1")
    try:
        logging.getLogger("test").info("hello", extra={"jobId": "job-1"})
    finally:
        correlation_id_var.reset(token)

    line = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert line["level"] == "info"
    assert line["msg"] == "hello"
    assert line["correlationId"] == "cid-1"
    assert line["jobId"] == "job-1"
    # pino の isoTime と同じ形（例：2026-11-03T06:09:02.991Z）
    assert line["time"].endswith("Z")
    assert "message" not in line


def test_no_correlation_id_outside_task(capsys: pytest.CaptureFixture[str]) -> None:
    configure_logging("info")
    logging.getLogger("test").info("hello")

    line = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert "correlationId" not in line

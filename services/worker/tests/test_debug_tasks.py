import json

import pytest

from app.logs import configure_logging
from app.tasks.debug import add


def test_add_returns_sum() -> None:
    assert add.run(2, 3) == 5


def test_add_logs_result_with_correlation_id(capsys: pytest.CaptureFixture[str]) -> None:
    configure_logging("info")

    # apply は SQS を通さずに、その場でタスクを実行する（実行の前後の signal も動く）
    result = add.apply(kwargs={"x": 4, "y": 5}, headers={"correlationId": "test-cid"})

    assert result.get() == 9
    lines = [json.loads(line) for line in capsys.readouterr().out.strip().splitlines()]
    line = next(line for line in lines if line["msg"] == "debug.add")
    assert line["result"] == 9
    assert line["correlationId"] == "test-cid"

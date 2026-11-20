from app.monitoring import scrub_event


def test_scrub_event_removes_messages_args_and_breadcrumbs() -> None:
    event = {
        "exception": {
            "values": [
                {
                    "type": "RuntimeError",
                    "value": "connect failed postgresql://worker:secret@db/yumeguri",
                    "stacktrace": {"frames": [{"filename": "app/tasks/debug.py", "lineno": 1}]},
                }
            ]
        },
        "extra": {"celery-job": {"args": ["secret"], "kwargs": {}}},
        "breadcrumbs": {"values": [{"message": "password=secret"}]},
    }

    scrubbed = scrub_event(event, None)

    exception = scrubbed["exception"]["values"][0]
    assert exception["type"] == "RuntimeError"
    assert exception["value"] == "[消した]"
    assert len(exception["stacktrace"]["frames"]) == 1
    assert "extra" not in scrubbed
    assert "breadcrumbs" not in scrubbed
    assert "secret" not in repr(scrubbed)

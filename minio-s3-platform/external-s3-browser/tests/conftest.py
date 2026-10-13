import importlib
import os
import sys

import pytest


@pytest.fixture()
def app_client(monkeypatch):
    """Reload app module with test env and return Flask test client."""
    monkeypatch.setenv("APP_SECRET_KEY", "test-secret-key-for-pytest-only")
    monkeypatch.setenv("MINIO_ENDPOINT", "http://minio:9000")
    monkeypatch.setenv("MINIO_AUTH_BUCKET", "developer-data")
    monkeypatch.setenv("MINIO_REGION", "us-east-1")
    monkeypatch.setenv("APPROVED_S3_BUCKETS", "approved-one,approved-two")
    monkeypatch.setenv("AWS_REGION", "ap-south-1")
    monkeypatch.setenv("COOKIE_SECURE", "false")

    if "app" in sys.modules:
        importlib.reload(sys.modules["app"])
    else:
        parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        sys.path.insert(0, parent)
        import app  # noqa: F401

    app_module = sys.modules["app"]
    app_module.app.config["TESTING"] = True
    app_module.app.config["WTF_CSRF_ENABLED"] = False

    with app_module.app.test_client() as client:
        yield client, app_module

import logging
from collections.abc import Callable, Iterator

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.db import Base, SessionLocal, engine
from app.main import app
from app.seed import seed_users


@pytest.fixture(scope="session", autouse=True)
def migrated_db() -> None:
    assert str(engine.url.database).endswith("_test"), "Run the tests with `make test`."
    command.upgrade(Config("alembic.ini"), "head")


@pytest.fixture(autouse=True)
def clean_db(migrated_db: None) -> None:
    tables = ", ".join(table.name for table in Base.metadata.sorted_tables)
    with engine.begin() as connection:
        connection.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
    with SessionLocal() as db:
        seed_users(db)
        db.commit()


@pytest.fixture
def client() -> Iterator[TestClient]:
    with TestClient(app) as client:
        yield client


@pytest.fixture
def app_logs(caplog: pytest.LogCaptureFixture) -> Callable[[], str]:
    """The API's own log output; the test client's request logs are not the API's."""
    caplog.set_level(logging.INFO, logger="diary.requests")
    return lambda: "\n".join(r.getMessage() for r in caplog.records if r.name == "diary.requests")

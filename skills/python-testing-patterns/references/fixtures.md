# Pytest Fixtures

## Basic Fixture (setup + teardown)

```python
import pytest
from typing import Generator

class Database:
    def __init__(self, connection_string: str):
        self.connection_string = connection_string
        self.connected = False

    def connect(self): self.connected = True
    def disconnect(self): self.connected = False

    def query(self, sql: str) -> list:
        if not self.connected:
            raise RuntimeError("Not connected")
        return [{"id": 1, "name": "Test"}]


@pytest.fixture
def db() -> Generator[Database, None, None]:
    """Connected database, cleaned up after the test."""
    database = Database("sqlite:///:memory:")
    database.connect()
    yield database
    database.disconnect()


def test_database_query(db):
    results = db.query("SELECT * FROM users")
    assert len(results) == 1
```

## Fixture Scopes

```python
@pytest.fixture(scope="session")  # once per test session
def app_config():
    return {"database_url": "postgresql://localhost/test", "debug": True}


@pytest.fixture(scope="module")  # once per test module
def api_client(app_config):
    client = {"config": app_config, "session": "active"}
    yield client
    client["session"] = "closed"
```

Available scopes: `function` (default), `class`, `module`, `package`, `session`.

## conftest.py — Shared Fixtures

```python
# conftest.py
import pytest

@pytest.fixture(scope="session")
def database_url():
    return "postgresql://localhost/test_db"


@pytest.fixture(autouse=True)
def reset_database(database_url):
    """autouse runs before/after every test in scope."""
    yield
    # teardown


@pytest.fixture
def sample_user():
    return {"id": 1, "name": "Test User", "email": "test@example.com"}


# Parametrized fixture: tests using it run once per param value
@pytest.fixture(params=["sqlite", "postgresql", "mysql"])
def db_backend(request):
    return request.param


def test_with_db_backend(db_backend):
    assert db_backend in ["sqlite", "postgresql", "mysql"]
```

## Async Fixtures

```python
@pytest.fixture
async def async_client():
    client = {"connected": True}
    yield client
    client["connected"] = False


@pytest.mark.asyncio
async def test_with_async_fixture(async_client):
    assert async_client["connected"] is True
```

## Tips

- Prefer fixtures over `setUp`/`tearDown` methods.
- Put shared fixtures in `conftest.py` at the appropriate level.
- Use `autouse=True` sparingly — implicit setup makes tests harder to read.
- Match scope to cost: expensive resources → `session`/`module`.

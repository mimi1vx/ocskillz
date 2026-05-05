# Integration Testing

## Database (SQLAlchemy + in-memory SQLite)

```python
import pytest
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.exc import IntegrityError

Base = declarative_base()


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    name = Column(String(50))
    email = Column(String(100), unique=True)


@pytest.fixture(scope="function")
def db_session() -> Session:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.close()


def test_create_user(db_session):
    user = User(name="Test User", email="test@example.com")
    db_session.add(user)
    db_session.commit()
    assert user.id is not None


def test_unique_email_constraint(db_session):
    db_session.add(User(name="A", email="same@example.com"))
    db_session.commit()
    db_session.add(User(name="B", email="same@example.com"))
    with pytest.raises(IntegrityError):
        db_session.commit()
```

## Temporary files (`tmp_path`)

```python
from pathlib import Path

def test_file_operations(tmp_path):
    test_file = tmp_path / "test_data.txt"
    test_file.write_text("Hello, World!")
    assert test_file.read_text() == "Hello, World!"


def test_multiple_files(tmp_path):
    files = {"a.txt": "1", "b.txt": "2"}
    for name, content in files.items():
        (tmp_path / name).write_text(content)
    assert len(list(tmp_path.iterdir())) == 2
```

`tmp_path` is a `pathlib.Path` auto-cleaned after the test.

## HTTP integration with `responses`

```python
import responses
import requests

@responses.activate
def test_api_call():
    responses.add(
        responses.GET,
        "https://api.example.com/users/1",
        json={"id": 1, "name": "Alice"},
        status=200,
    )
    resp = requests.get("https://api.example.com/users/1")
    assert resp.json()["name"] == "Alice"
```

## Tips

- Use real (in-memory) databases over heavy mocks when feasible.
- Mark slow integration tests with `@pytest.mark.integration` and gate in CI.
- Reset state between tests via function-scoped fixtures.

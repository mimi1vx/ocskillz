# Mocking and Monkeypatching

## unittest.mock

```python
import pytest
from unittest.mock import Mock, patch
import requests

class APIClient:
    def __init__(self, base_url: str):
        self.base_url = base_url

    def get_user(self, user_id: int) -> dict:
        response = requests.get(f"{self.base_url}/users/{user_id}")
        response.raise_for_status()
        return response.json()


def test_get_user_success():
    client = APIClient("https://api.example.com")
    mock_response = Mock()
    mock_response.json.return_value = {"id": 1, "name": "John Doe"}
    mock_response.raise_for_status.return_value = None

    with patch("requests.get", return_value=mock_response) as mock_get:
        user = client.get_user(1)
        assert user["name"] == "John Doe"
        mock_get.assert_called_once_with("https://api.example.com/users/1")


def test_get_user_not_found():
    client = APIClient("https://api.example.com")
    mock_response = Mock()
    mock_response.raise_for_status.side_effect = requests.HTTPError("404")

    with patch("requests.get", return_value=mock_response):
        with pytest.raises(requests.HTTPError):
            client.get_user(999)


@patch("requests.post")
def test_create_user(mock_post):
    """Decorator form."""
    mock_post.return_value.json.return_value = {"id": 2}
    mock_post.return_value.raise_for_status.return_value = None
    # ... call code under test ...
```

## monkeypatch (pytest built-in)

```python
import os

def get_database_url() -> str:
    return os.environ.get("DATABASE_URL", "sqlite:///:memory:")


def test_database_url_custom(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://localhost/test")
    assert get_database_url() == "postgresql://localhost/test"


def test_database_url_not_set(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    assert get_database_url() == "sqlite:///:memory:"


class Config:
    def __init__(self):
        self.api_key = "production-key"


def test_monkeypatch_attribute(monkeypatch):
    config = Config()
    monkeypatch.setattr(config, "api_key", "test-key")
    assert config.api_key == "test-key"
```

`monkeypatch` auto-reverts at end of test. Prefer it over `unittest.mock.patch` for env vars and attributes.

## Testing Retry Behaviour

```python
from unittest.mock import Mock

def test_retries_on_transient_error():
    client = Mock()
    client.request.side_effect = [
        ConnectionError("Failed"),
        ConnectionError("Failed"),
        {"status": "ok"},
    ]
    service = ServiceWithRetry(client, max_retries=3)
    result = service.fetch()
    assert result == {"status": "ok"}
    assert client.request.call_count == 3


def test_does_not_retry_on_permanent_error():
    client = Mock()
    client.request.side_effect = ValueError("Invalid input")
    service = ServiceWithRetry(client, max_retries=3)
    with pytest.raises(ValueError):
        service.fetch()
    assert client.request.call_count == 1
```

## When to mock — and when not to

- **Mock external I/O**: HTTP, files (sometimes), DBs (often), time, random.
- **Don't mock the code under test** — that just tests the mock.
- **Prefer `responses` library** for `requests` HTTP mocking; cleaner than `patch`.

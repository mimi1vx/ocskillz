# Async Testing

Requires `pytest-asyncio` (or `anyio` plugin).

```bash
uv add --group dev pytest-asyncio
```

## Basic async test

```python
import pytest
import asyncio

async def fetch_data(url: str) -> dict:
    await asyncio.sleep(0.1)
    return {"url": url, "data": "result"}


@pytest.mark.asyncio
async def test_fetch_data():
    result = await fetch_data("https://api.example.com")
    assert result["url"] == "https://api.example.com"
```

## Concurrent operations

```python
@pytest.mark.asyncio
async def test_concurrent_fetches():
    urls = ["url1", "url2", "url3"]
    tasks = [fetch_data(url) for url in urls]
    results = await asyncio.gather(*tasks)
    assert len(results) == 3
```

## Async fixtures

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

## Auto mode

In `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

This treats every `async def test_*` as `@pytest.mark.asyncio` automatically.

## Tips

- Use `asyncio.wait_for(..., timeout=...)` to fail fast on hangs.
- Mock async calls with `unittest.mock.AsyncMock`.
- Prefer `anyio` if you may target trio in addition to asyncio.

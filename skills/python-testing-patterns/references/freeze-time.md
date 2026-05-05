# Freezing Time with `freezegun`

```bash
uv add --group dev freezegun
```

## Decorator form

```python
from freezegun import freeze_time
from datetime import datetime

@freeze_time("2026-01-15 10:00:00")
def test_token_expiry():
    token = create_token(expires_in_seconds=3600)
    assert token.expires_at == datetime(2026, 1, 15, 11, 0, 0)


@freeze_time("2026-01-15 10:00:00")
def test_is_expired_returns_false_before_expiry():
    token = create_token(expires_in_seconds=3600)
    assert not token.is_expired()
```

## Context manager + time travel

```python
def test_with_time_travel():
    with freeze_time("2026-01-01") as frozen:
        item = create_item()
        assert item.created_at == datetime(2026, 1, 1)
        frozen.move_to("2026-01-15")
        assert item.age_days == 14
```

## Tips

- Freeze time at the boundaries you actually rely on (`now()`, `utcnow()`, `time.time()`).
- For tests that don't need full time control, prefer injecting a `clock` callable instead of patching globally.
- `freezegun` ticks can be enabled via `tick=True` if you need natural progression.

# Parametrized Tests

## Basic parametrize

```python
import pytest

def is_valid_email(email: str) -> bool:
    return "@" in email and "." in email.split("@")[1]


@pytest.mark.parametrize("email,expected", [
    ("user@example.com", True),
    ("test.user@domain.co.uk", True),
    ("invalid.email", False),
    ("@example.com", False),
    ("user@domain", False),
    ("", False),
])
def test_email_validation(email, expected):
    assert is_valid_email(email) == expected
```

## Custom IDs with `pytest.param`

```python
@pytest.mark.parametrize("value,expected", [
    pytest.param(1, True, id="positive"),
    pytest.param(0, False, id="zero"),
    pytest.param(-1, False, id="negative"),
])
def test_is_positive(value, expected):
    assert (value > 0) == expected
```

## Stacking parametrize (Cartesian product)

```python
@pytest.mark.parametrize("backend", ["sqlite", "postgresql"])
@pytest.mark.parametrize("isolation", ["read_committed", "serializable"])
def test_combinations(backend, isolation):
    # runs 2 × 2 = 4 times
    ...
```

## Markers in parametrize

```python
@pytest.mark.parametrize("n,expected", [
    (1, 1),
    pytest.param(2, 2, marks=pytest.mark.skip(reason="flaky")),
    pytest.param(1_000_000, 1_000_000, marks=pytest.mark.slow),
])
def test_identity(n, expected):
    assert n == expected
```

## Tips

- One row per scenario keeps failures isolated.
- Use `id=...` for readable test names in failure output.
- Don't parametrize what would be clearer as separate named tests (rule of thumb: > 3 truly distinct behaviors → split).

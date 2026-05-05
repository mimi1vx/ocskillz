# Test Design Principles

## One Behavior Per Test

Each test verifies exactly one behavior. Failures point to one cause.

```python
# BAD — multiple behaviors mixed
def test_user_service():
    user = service.create_user(data)
    assert user.id is not None
    assert user.email == data["email"]
    updated = service.update_user(user.id, {"name": "New"})
    assert updated.name == "New"

# GOOD — focused tests
def test_create_user_assigns_id():
    assert service.create_user(data).id is not None

def test_create_user_stores_email():
    assert service.create_user(data).email == data["email"]

def test_update_user_changes_name():
    user = service.create_user(data)
    assert service.update_user(user.id, {"name": "New"}).name == "New"
```

## Test Error Paths

```python
def test_get_user_raises_not_found():
    with pytest.raises(UserNotFoundError) as exc_info:
        service.get_user("nonexistent-id")
    assert "nonexistent-id" in str(exc_info.value)


def test_create_user_rejects_invalid_email():
    with pytest.raises(ValueError, match="Invalid email format"):
        service.create_user({"email": "not-an-email"})
```

## Exception Testing Patterns

```python
import pytest

def test_zero_division():
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)


def test_zero_division_with_message():
    with pytest.raises(ZeroDivisionError, match="Division by zero"):
        divide(5, 0)


def test_exception_info():
    with pytest.raises(ValueError) as exc_info:
        int("not a number")
    assert "invalid literal" in str(exc_info.value)
```

## Naming Convention

Pattern: `test_<unit>_<scenario>_<expected_outcome>`

```python
def test_create_user_with_valid_data_returns_user(): ...
def test_create_user_with_duplicate_email_raises_conflict(): ...
def test_login_fails_with_invalid_password(): ...
def test_api_returns_404_for_missing_resource(): ...

# Avoid:
def test_1(): ...        # not descriptive
def test_user(): ...     # too vague
def test_function(): ... # what is being tested?
```

## Test Organization

```
tests/
├── __init__.py
├── conftest.py              # shared fixtures
├── test_models.py
├── test_utils.py
├── integration/
│   ├── test_api.py
│   └── test_database.py
└── e2e/
    └── test_workflows.py
```

## Property-Based Testing (Hypothesis)

```bash
uv add --group dev hypothesis
```

```python
from hypothesis import given, strategies as st

def reverse_string(s: str) -> str:
    return s[::-1]


@given(st.text())
def test_reverse_twice_is_original(s):
    assert reverse_string(reverse_string(s)) == s


@given(st.text())
def test_reverse_length(s):
    assert len(reverse_string(s)) == len(s)


@given(st.lists(st.integers()))
def test_sorted_list_properties(lst):
    sorted_lst = sorted(lst)
    assert len(sorted_lst) == len(lst)
    assert set(sorted_lst) == set(lst)
    for i in range(len(sorted_lst) - 1):
        assert sorted_lst[i] <= sorted_lst[i + 1]
```

Use property-based tests for: serialization round-trips, mathematical invariants, parser/lexer behavior, idempotent operations.

## AAA Pattern

- **Arrange** — set up data and preconditions
- **Act** — invoke the code under test
- **Assert** — verify the result

```python
def test_discount_application():
    # Arrange
    cart = Cart(items=[Item(price=100), Item(price=50)])
    coupon = Coupon(percent=10)

    # Act
    total = cart.apply(coupon).total()

    # Assert
    assert total == 135
```

## Summary Checklist

1. Write tests first (TDD) or alongside code
2. One behavior per test
3. Descriptive names that explain the scenario
4. Tests are independent and isolated
5. Use fixtures for setup/teardown
6. Mock external dependencies, not internal logic
7. Parametrize to reduce duplication
8. Test edge cases and error paths
9. Measure coverage but value quality over %
10. Run tests in CI on every commit

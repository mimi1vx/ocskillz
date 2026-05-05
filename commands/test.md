---
description: Run tests with coverage - python
agent: build
---

Run the full test suite with coverage report and show any failures.
Focus on the failing tests and suggest fixes.

For the test run, prefer `uv run pytest` first. If `uv` is not available, fall back to `python3 -m pytest`.
Use the pytest-cov plugin for coverage.
When using the fallback, run inside a virtual env activated by `source .env/bin/activate` and assume all needed tools are installed.

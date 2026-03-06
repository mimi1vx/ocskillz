---
description: Run tests with coverage - python
agent: build
---

Run the full test suite with coverage report and show any failures.
Focus on the failing tests and suggest fixes.

For test run command `python3 -m pytest` and use cov pluging of pytest for coverage.
Always run in virtual env, started by `source .env/bin/activate` and except all needed tool are installed

.PHONY: help install dev lint format typecheck test clean

help:
	@echo "Available targets:"
	@echo "  install     - Install project dependencies"
	@echo "  dev         - Install all dependencies including dev"
	@echo "  lint        - Run ruff linter"
	@echo "  format      - Format code with ruff"
	@echo "  typecheck   - Run type checking with ty"
	@echo "  test        - Run tests with pytest"
	@echo "  clean       - Remove build artifacts"

install:
	uv sync

dev:
	uv sync --all-groups

lint:
	uv run ruff check .

format:
	uv  format .

typecheck:
	uv run ty check src/

test:
	python3 -m pytest

clean:
	rm -rf build/ dist/ *.egg-info
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

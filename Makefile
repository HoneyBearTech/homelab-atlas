.PHONY: test lint check config

PYTHON ?= python3
VENV := .venv

# Check and test tools, pinned with hashes; the venv is rebuilt when the requirements change
$(VENV)/.installed: requirements-dev.txt
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes --no-deps -r requirements-dev.txt
	touch $@

# Unit tests for the policy checker, with the coverage floor from pyproject.toml (no Docker, no network)
test: $(VENV)/.installed
	$(VENV)/bin/coverage run -m pytest -q
	$(VENV)/bin/coverage report

# The Python and YAML linters CI runs (the workflow and secret scanners run in containers; see ci.yml)
lint: $(VENV)/.installed
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .
	$(VENV)/bin/yamllint --strict .

# The stack's policy check: every image pinned by digest, nothing privileged (needs Docker and .env)
check: $(VENV)/.installed
	docker compose config --format json | $(VENV)/bin/python scripts/check_compose.py

# Print the resolved Compose file, with .env applied
config:
	docker compose config

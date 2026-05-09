#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT/src"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if [[ -n "${PAS_BIN:-}" ]]; then
  exec "$PAS_BIN" --config "$PROJECT_ROOT/config.toml" --env "$PROJECT_ROOT/.env" "$@"
fi

if [[ -x "$PROJECT_ROOT/bin/pas" ]]; then
  exec "$PROJECT_ROOT/bin/pas" --config "$PROJECT_ROOT/config.toml" --env "$PROJECT_ROOT/.env" "$@"
fi

exec "$PYTHON_BIN" -m pas_automation.cli \
  --config "$PROJECT_ROOT/config.toml" \
  --env "$PROJECT_ROOT/.env" \
  "$@"

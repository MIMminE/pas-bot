#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

missing=0

check_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing file: $1"
    missing=1
  fi
}

check_file "$PROJECT_ROOT/config.toml"

if [[ -f "$PROJECT_ROOT/config.toml" ]]; then
  grep -q 'api_token = "[^"]' "$PROJECT_ROOT/config.toml" || {
    echo "missing config: jira.api_token"
    missing=1
  }
  grep -q 'webhook_url = "https://hooks.slack.com/services/' "$PROJECT_ROOT/config.toml" || {
    echo "missing config: slack.webhook_url"
    missing=1
  }
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing command: python3"
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  echo "Setup check failed."
  exit 1
fi

echo "Setup check passed."
echo "Run CLI: scripts/run-pas.sh --help"
echo "Try Slack test: scripts/test-slack-now.sh"
echo "Send Jira briefing now: scripts/test-jira-slack-now.sh"

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

check_env() {
  if [[ -z "${!1:-}" ]]; then
    echo "missing env: $1"
    missing=1
  fi
}

check_file "$PROJECT_ROOT/config.toml"
check_file "$PROJECT_ROOT/.env"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    export "$key=$value"
  done < "$PROJECT_ROOT/.env"
fi

check_env JIRA_API_TOKEN
check_env SLACK_WEBHOOK_URL

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

#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="$HOME/Library/LaunchAgents"
LABEL="com.pas.jira-daily"
TARGET_PLIST="$AGENT_DIR/$LABEL.plist"

mkdir -p "$AGENT_DIR" "$PROJECT_ROOT/.pas/logs"
chmod +x "$PROJECT_ROOT/scripts/send-jira-daily.sh"

sed "s#/Users/yourname/PAS#$PROJECT_ROOT#g" \
  "$PROJECT_ROOT/launchd/$LABEL.plist" > "$TARGET_PLIST"

launchctl unload "$TARGET_PLIST" >/dev/null 2>&1 || true
launchctl load "$TARGET_PLIST"

echo "Installed $LABEL"
echo "Run now: launchctl start $LABEL"
echo "Logs:"
echo "  $PROJECT_ROOT/.pas/logs/jira-daily.out.log"
echo "  $PROJECT_ROOT/.pas/logs/jira-daily.err.log"

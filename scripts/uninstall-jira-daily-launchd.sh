#!/usr/bin/env bash
set -euo pipefail

LABEL="com.pas.jira-daily"
TARGET_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$TARGET_PLIST" >/dev/null 2>&1 || true
rm -f "$TARGET_PLIST"

echo "Uninstalled $LABEL"

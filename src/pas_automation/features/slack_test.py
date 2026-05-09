from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.slack import SlackWebhook


def send_test_message(config: AppConfig, *, dry_run: bool) -> str:
    now = datetime.now(ZoneInfo(config.general.timezone)).strftime("%Y-%m-%d %H:%M:%S")
    message = f"PAS Slack webhook test - {now}"
    if dry_run:
        return "[dry-run]\n" + message
    SlackWebhook(config.slack).send(message)
    return "Slack 테스트 메시지를 전송했습니다."

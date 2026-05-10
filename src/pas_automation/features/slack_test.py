from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.slack import SlackWebhook, context_block, header_block, section_block


def send_test_message(config: AppConfig, *, dry_run: bool, destination: str = "test") -> str:
    now = datetime.now(ZoneInfo(config.general.timezone)).strftime("%Y-%m-%d %H:%M:%S")
    message = f"PAS Slack webhook test ({destination}) - {now}"
    blocks = [
        header_block("PAS 연결 테스트"),
        section_block(f"*Slack webhook 연결이 정상입니다.*\n목적지: `{destination}`"),
        context_block(f"전송 시각: {now} | timezone: {config.general.timezone}"),
    ]
    if dry_run:
        return "[dry-run]\n" + message
    SlackWebhook(config.slack, destination=destination).send(message, blocks=blocks)
    return "Slack 테스트 메시지를 전송했습니다."

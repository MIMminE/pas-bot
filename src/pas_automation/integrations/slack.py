from __future__ import annotations
from typing import Any

from pas_automation.config import SlackConfig
from pas_automation.http import json_request


class SlackWebhook:
    def __init__(self, config: SlackConfig, *, destination: str = "default") -> None:
        webhook_url = config.webhook_for(destination)
        if not webhook_url:
            raise RuntimeError(
                "Slack Webhook URL이 설정되어 있지 않습니다. "
                f"config.toml의 [slack.webhooks].{destination} 또는 [slack].webhook_url 값을 입력해 주세요."
            )
        self.webhook_url = webhook_url

    def send(self, text: str, *, blocks: list[dict[str, Any]] | None = None) -> None:
        payload: dict[str, Any] = {"text": text}
        if blocks:
            payload["blocks"] = blocks
        json_request("POST", self.webhook_url, payload=payload)


def header_block(text: str) -> dict[str, Any]:
    return {"type": "header", "text": {"type": "plain_text", "text": _clip(text, 150), "emoji": True}}


def section_block(text: str) -> dict[str, Any]:
    return {"type": "section", "text": {"type": "mrkdwn", "text": _clip(text, 3000)}}


def fields_block(fields: list[str]) -> dict[str, Any]:
    return {
        "type": "section",
        "fields": [{"type": "mrkdwn", "text": _clip(field, 2000)} for field in fields[:10]],
    }


def context_block(text: str) -> dict[str, Any]:
    return {"type": "context", "elements": [{"type": "mrkdwn", "text": _clip(text, 3000)}]}


def divider_block() -> dict[str, Any]:
    return {"type": "divider"}


def _clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 3].rstrip() + "..."

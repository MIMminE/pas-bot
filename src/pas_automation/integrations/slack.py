from __future__ import annotations
from typing import Any
from urllib.parse import urlencode

from pas_automation.config import SlackConfig
from pas_automation.http import json_request

SLACK_API_BASE = "https://slack.com/api"


class SlackClient:
    def __init__(self, config: SlackConfig, *, destination: str = "default") -> None:
        self.config = config
        self.destination = destination
        self.channel = config.channel_for(destination)

        if not config.bot_token:
            raise RuntimeError("Slack Bot Token이 설정되어 있지 않습니다. config.toml의 [slack].bot_token 값을 입력해 주세요.")
        if not self.channel:
            raise RuntimeError(
                f"Slack 채널이 설정되어 있지 않습니다. config.toml의 [slack.channels].{destination} 값을 선택해 주세요."
            )

    def send(self, text: str, *, blocks: list[dict[str, Any]] | None = None) -> None:
        payload: dict[str, Any] = {"text": text}
        if blocks:
            payload["blocks"] = blocks
        payload["channel"] = self.channel
        response = json_request(
            "POST",
            f"{SLACK_API_BASE}/chat.postMessage",
            headers={"Authorization": f"Bearer {self.config.bot_token}"},
            payload=payload,
        )
        _raise_for_slack_error(response)


def list_channels(config: SlackConfig) -> list[dict[str, str]]:
    if not config.bot_token:
        raise RuntimeError("Slack 채널 목록을 불러오려면 [slack].bot_token 값이 필요합니다.")

    channels: list[dict[str, str]] = []
    cursor = ""
    while True:
        query = {"types": "public_channel,private_channel", "limit": "200"}
        if cursor:
            query["cursor"] = cursor
        url = f"{SLACK_API_BASE}/conversations.list?{urlencode(query)}"
        response = json_request(
            "GET",
            url,
            headers={"Authorization": f"Bearer {config.bot_token}"},
        )
        _raise_for_slack_error(response)
        for item in response.get("channels", []):
            channels.append(
                {
                    "id": str(item.get("id", "")),
                    "name": str(item.get("name", "")),
                    "is_private": "true" if item.get("is_private") else "false",
                }
            )
        cursor = str(response.get("response_metadata", {}).get("next_cursor", ""))
        if not cursor:
            return channels


def _raise_for_slack_error(response: Any) -> None:
    if isinstance(response, dict) and response.get("ok") is False:
        raise RuntimeError(f"Slack API 오류: {response.get('error', 'unknown_error')}")


def header_block(text: str) -> dict[str, Any]:
    return {"type": "header", "text": {"type": "plain_text", "text": _clip(text, 150), "emoji": True}}


def section_block(text: str) -> dict[str, Any]:
    return {"type": "section", "text": {"type": "mrkdwn", "text": _clip(text, 3000)}}


def fields_block(fields: list[str]) -> dict[str, Any]:
    return {
        "type": "section",
        "fields": [{"type": "mrkdwn", "text": _clip(field, 2000)} for field in fields[:10]],
    }


def actions_block(elements: list[dict[str, Any]]) -> dict[str, Any]:
    return {"type": "actions", "elements": elements[:5]}


def button_element(text: str, url: str, *, action_id: str) -> dict[str, Any]:
    return {
        "type": "button",
        "text": {"type": "plain_text", "text": _clip(text, 75), "emoji": True},
        "url": url,
        "action_id": action_id,
    }


def context_block(text: str) -> dict[str, Any]:
    return {"type": "context", "elements": [{"type": "mrkdwn", "text": _clip(text, 3000)}]}


def divider_block() -> dict[str, Any]:
    return {"type": "divider"}


def _clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 3].rstrip() + "..."

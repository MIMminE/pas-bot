from __future__ import annotations

import os

from pas_automation.config import SlackConfig
from pas_automation.http import json_request


class SlackWebhook:
    def __init__(self, config: SlackConfig) -> None:
        webhook_url = os.environ.get(config.webhook_url_env)
        if not webhook_url:
            raise RuntimeError(f"Missing Slack webhook environment variable: {config.webhook_url_env}")
        self.webhook_url = webhook_url

    def send(self, text: str) -> None:
        payload = {"text": text}
        json_request("POST", self.webhook_url, payload=payload)

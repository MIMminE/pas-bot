from __future__ import annotations

import os

from pas_automation.config import OpenAIConfig
from pas_automation.http import json_request


def build_report(config: OpenAIConfig, commits_text: str) -> str:
    api_key = os.environ.get(config.api_key_env)
    if not api_key:
        return fallback_report(commits_text)

    payload = {
        "model": config.model,
        "input": [
            {
                "role": "system",
                "content": "You write concise Korean daily work reports from git commits. Group related work and avoid exaggeration.",
            },
            {
                "role": "user",
                "content": (
                    "아래 git commit 목록을 기반으로 오늘 한 일 보고서를 한국어로 작성해줘. "
                    "Slack에 바로 올릴 수 있게 제목, 핵심 작업, 참고/리스크 순서로 간결하게 정리해줘.\n\n"
                    f"{commits_text}"
                ),
            },
        ],
    }
    response = json_request(
        "POST",
        "https://api.openai.com/v1/responses",
        headers={"Authorization": f"Bearer {api_key}"},
        payload=payload,
        timeout=60,
    )
    if response.get("output_text"):
        return response["output_text"].strip()
    for item in response.get("output", []):
        for content in item.get("content", []):
            if content.get("type") == "output_text" and content.get("text"):
                return content["text"].strip()
    raise RuntimeError("OpenAI response did not include output text.")


def fallback_report(commits_text: str) -> str:
    if not commits_text.strip():
        return "오늘 git 커밋 기준으로 확인된 작업 내역이 없습니다."
    return "오늘 한 일 초안\n\n" + commits_text

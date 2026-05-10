from __future__ import annotations

from pas_automation.config import OpenAIConfig
from pas_automation.http import json_request


TONE_INSTRUCTIONS = {
    "brief": "짧고 핵심만 남긴다. 불필요한 수식어를 줄인다.",
    "detailed": "맥락, 작업 범위, 확인 사항을 조금 더 자세히 정리한다.",
    "manager": "관리자가 빠르게 판단할 수 있게 성과, 리스크, 다음 액션 중심으로 정리한다.",
}


def generate_text(config: OpenAIConfig, *, system: str, prompt: str, fallback: str) -> str:
    api_key = config.api_key
    if not api_key:
        return fallback

    payload = {
        "model": config.model,
        "input": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
    }
    response = json_request(
        "POST",
        "https://api.openai.com/v1/responses",
        headers={"Authorization": f"Bearer {api_key}"},
        payload=payload,
        timeout=60,
    )
    return _extract_output_text(response)


def build_report(config: OpenAIConfig, commits_text: str) -> str:
    return generate_text(
        config,
        system=(
            "You write concise Korean daily work reports from git repository evidence. "
            "Use repository status, branch, sync hints, and commit messages as evidence. "
            "Group related work, avoid exaggeration, and mention uncertainty when the commit message is vague."
        ),
        prompt=(
            "아래 로컬 Git repository 상태와 커밋 목록을 기반으로 오늘 작업 보고서를 한국어로 작성해줘. "
            "Slack에 바로 보낼 수 있게 제목, 핵심 작업, 확인 필요/리스크 순서로 간결하게 정리해줘. "
            "rebase/pull/push 필요 여부도 참고 항목에 반영해줘.\n\n"
            f"{commits_text}"
        ),
        fallback=fallback_report(commits_text),
    )


def tone_instruction(tone: str) -> str:
    return TONE_INSTRUCTIONS.get(tone, TONE_INSTRUCTIONS["brief"])


def _extract_output_text(response: dict) -> str:
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
    return "오늘 작업 초안\n\n" + commits_text

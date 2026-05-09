from __future__ import annotations

from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.slack import (
    SlackWebhook,
    context_block,
    divider_block,
    fields_block,
    header_block,
    section_block,
)


def format_today_items(
    config: AppConfig,
    *,
    max_results: int = 25,
    dry_run: bool = False,
    send_slack: bool = False,
) -> str:
    if dry_run:
        return "\n".join(
            [
                "[dry-run] Jira daily briefing",
                f"base_url: {config.jira.base_url}",
                f"email: {config.jira.email}",
                f"default_project: {config.jira.default_project}",
                f"todo_jql: {config.jira.todo_jql}",
                f"yesterday_assigned_jql: {config.jira.yesterday_assigned_jql}",
                f"stale_jql: {config.jira.stale_jql}",
                f"high_priority_jql: {config.jira.high_priority_jql}",
            ]
        )

    client = JiraClient(config.jira)
    issues = client.search(config.jira.todo_jql, max_results=max_results)
    yesterday_keys = _issue_keys(client.search(config.jira.yesterday_assigned_jql, max_results=100))
    stale_keys = _issue_keys(client.search(config.jira.stale_jql, max_results=100))
    high_keys = _issue_keys(client.search(config.jira.high_priority_jql, max_results=100))

    today = datetime.now(ZoneInfo(config.general.timezone)).date().isoformat()
    lines = _build_text_report(config, today, issues, yesterday_keys, stale_keys, high_keys)

    message = "\n".join(lines)
    if send_slack:
        SlackWebhook(config.slack).send(
            message,
            blocks=_build_slack_blocks(config, today, issues, yesterday_keys, stale_keys, high_keys),
        )
    return message


def assign_issue(config: AppConfig, issue_key: str, account_id_or_email: str, *, dry_run: bool) -> str:
    if dry_run:
        return f"[dry-run] Assign {issue_key} to {account_id_or_email}"
    JiraClient(config.jira).assign_issue(issue_key, account_id_or_email)
    return f"{issue_key} 이슈를 {account_id_or_email}에게 할당했습니다."


def _build_text_report(
    config: AppConfig,
    today: str,
    issues: list[dict[str, Any]],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
) -> list[str]:
    lines = [
        f"오늘의 Jira 일감 - {today}",
        (
            "오늘의 Jira 일감: "
            f"미처리 {len(issues)}개, "
            f"어제 할당 {len(yesterday_keys)}개, "
            f"5일 이상 {len(stale_keys)}개, "
            f"높은 우선순위 {len(high_keys)}개"
        ),
        "",
        "내게 할당된 미처리 일감",
    ]

    if not issues:
        lines.append("확인할 미처리 일감이 없습니다.")
    else:
        for issue in issues:
            lines.extend(_format_issue(config, issue, yesterday_keys, stale_keys, high_keys))
    return lines


def _build_slack_blocks(
    config: AppConfig,
    today: str,
    issues: list[dict[str, Any]],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
) -> list[dict[str, Any]]:
    blocks = [
        header_block(f"오늘의 Jira 일감 - {today}"),
        fields_block(
            [
                f"*미처리*\n{len(issues)}개",
                f"*어제 할당*\n{len(yesterday_keys)}개",
                f"*5일 이상 미갱신*\n{len(stale_keys)}개",
                f"*높은 우선순위*\n{len(high_keys)}개",
            ]
        ),
        divider_block(),
    ]

    if not issues:
        blocks.append(section_block("확인할 미처리 일감이 없습니다."))
        return blocks

    for issue in issues[:10]:
        blocks.append(section_block(_format_issue_markdown(config, issue, yesterday_keys, stale_keys, high_keys)))

    if len(issues) > 10:
        blocks.append(context_block(f"Slack 표시 한도 때문에 상위 10개만 표시했습니다. 전체 조회 결과: {len(issues)}개"))

    return blocks[:50]


def _format_issue(
    config: AppConfig,
    issue: dict[str, Any],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
) -> list[str]:
    fields = issue["fields"]
    priority = fields.get("priority", {}) or {}
    status = fields.get("status", {}) or {}
    due = fields.get("duedate") or "-"
    badges = _badges(issue["key"], yesterday_keys, stale_keys, high_keys)
    badge_text = "".join(f" [{badge}]" for badge in badges)
    description = _truncate(_description_to_text(fields.get("description")), 220)
    return [
        "",
        f"{issue['key']}{badge_text} {fields.get('summary', '')}",
        f"상태: {status.get('name', 'Unknown')} | 우선순위: {priority.get('name', '-')} | 마감: {due}",
        f"링크: {_issue_url(config, issue['key'])}",
        f"내용: {description}",
    ]


def _format_issue_markdown(
    config: AppConfig,
    issue: dict[str, Any],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
) -> str:
    fields = issue["fields"]
    priority = fields.get("priority", {}) or {}
    status = fields.get("status", {}) or {}
    due = fields.get("duedate") or "-"
    badges = " ".join(f"`{badge}`" for badge in _badges(issue["key"], yesterday_keys, stale_keys, high_keys))
    description = _truncate(_description_to_text(fields.get("description")), 180)
    title = f"<{_issue_url(config, issue['key'])}|{issue['key']}> {fields.get('summary', '')}"
    meta = f"상태: {status.get('name', 'Unknown')} | 우선순위: {priority.get('name', '-')} | 마감: {due}"
    suffix = f"\n{badges}" if badges else ""
    return f"*{title}*\n{meta}{suffix}\n>{description}"


def _badges(issue_key: str, yesterday_keys: set[str], stale_keys: set[str], high_keys: set[str]) -> list[str]:
    badges = []
    if issue_key in yesterday_keys:
        badges.append("어제 할당")
    if issue_key in high_keys:
        badges.append("높은 우선순위")
    if issue_key in stale_keys:
        badges.append("5일 이상")
    return badges


def _issue_url(config: AppConfig, issue_key: str) -> str:
    return f"{config.jira.base_url}/browse/{issue_key}"


def _issue_keys(issues: list[dict[str, Any]]) -> set[str]:
    return {issue["key"] for issue in issues}


def _description_to_text(value: object) -> str:
    if not value:
        return "-"
    if isinstance(value, str):
        return " ".join(value.split())
    if isinstance(value, dict):
        parts: list[str] = []
        _walk_adf(value, parts)
        text = " ".join(" ".join(parts).split())
        return text or "-"
    return str(value)


def _walk_adf(node: object, parts: list[str]) -> None:
    if isinstance(node, dict):
        if node.get("type") == "text" and node.get("text"):
            parts.append(str(node["text"]))
        for child in node.get("content", []):
            _walk_adf(child, parts)
    elif isinstance(node, list):
        for child in node:
            _walk_adf(child, parts)


def _truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."

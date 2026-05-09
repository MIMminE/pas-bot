from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.slack import SlackWebhook


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
        lines.append("확인된 미처리 일감이 없습니다.")
    else:
        for issue in issues:
            lines.extend(_format_issue(issue, yesterday_keys, stale_keys, high_keys))

    message = "\n".join(lines)
    if send_slack:
        SlackWebhook(config.slack).send(message)
    return message


def assign_issue(config: AppConfig, issue_key: str, account_id_or_email: str, *, dry_run: bool) -> str:
    if dry_run:
        return f"[dry-run] Assign {issue_key} to {account_id_or_email}"
    JiraClient(config.jira).assign_issue(issue_key, account_id_or_email)
    return f"{issue_key} 이슈를 {account_id_or_email}에게 할당했습니다."


def _format_issue(
    issue: dict,
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
) -> list[str]:
    fields = issue["fields"]
    priority = fields.get("priority", {}) or {}
    status = fields.get("status", {}) or {}
    due = fields.get("duedate") or "-"
    badges = []
    if issue["key"] in yesterday_keys:
        badges.append("어제 할당")
    if issue["key"] in high_keys:
        badges.append("높은 우선순위")
    if issue["key"] in stale_keys:
        badges.append("5일 이상")

    badge_text = "".join(f" [{badge}]" for badge in badges)
    description = _truncate(_description_to_text(fields.get("description")), 220)
    return [
        "",
        f"{issue['key']}{badge_text} {fields.get('summary', '')}",
        f"상태: {status.get('name', 'Unknown')} | 우선순위: {priority.get('name', '-')} | 마감: {due}",
        f"내용: {description}",
    ]


def _issue_keys(issues: list[dict]) -> set[str]:
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

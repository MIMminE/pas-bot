from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from zoneinfo import ZoneInfo

from pas_automation.app_state import read_state, write_state
from pas_automation.config import AppConfig
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.slack import SlackClient, section_block


STATE_KEY = "jira_issue_watch"


def check_new_issues(
    config: AppConfig,
    *,
    jql: str = "",
    max_results: int = 20,
    include_existing: bool = False,
    send_slack: bool = False,
) -> str:
    if not config.features.jira:
        return "Jira 기능이 꺼져 있습니다."

    state = read_state()
    watch = state.setdefault(STATE_KEY, {})
    timezone = ZoneInfo(config.general.timezone)
    now = datetime.now(timezone)
    last_checked = _parse_datetime(watch.get("last_checked_at"), timezone)

    base_jql = _base_jql(config, jql)
    if not last_checked and not include_existing:
        watch["last_checked_at"] = now.isoformat()
        watch["seen_keys"] = watch.get("seen_keys", [])
        write_state(state)
        return f"Jira 새 일감 감시 기준점을 설정했습니다: {now.strftime('%Y-%m-%d %H:%M')}"

    since = last_checked - timedelta(minutes=2) if last_checked else now - timedelta(days=1)
    final_jql = _watch_jql(base_jql, since)
    issues = JiraClient(config.jira).search(final_jql, max_results=max_results)

    seen_keys = set(str(key) for key in watch.get("seen_keys", []))
    new_issues = [issue for issue in issues if issue.get("key") not in seen_keys]
    new_issues.sort(key=lambda issue: _issue_created(issue), reverse=False)

    watch["last_checked_at"] = now.isoformat()
    watch["seen_keys"] = _trim_seen_keys([*(issue.get("key", "") for issue in new_issues), *seen_keys])
    write_state(state)

    if not new_issues:
        return f"새로 등록된 Jira 일감이 없습니다. 기준: {since.strftime('%Y-%m-%d %H:%M')}"

    output = _format_issues(config, new_issues)
    if send_slack and config.slack.destination_configured("alerts"):
        SlackClient(config.slack, destination="alerts").send(output, blocks=[section_block(output)])
    return output


def _base_jql(config: AppConfig, jql: str) -> str:
    value = _strip_order_by((jql or config.jira_issue_watch.jql).strip())
    if value:
        return value
    project = config.jira.default_project.strip()
    if project:
        return f"project = {project}"
    return ""


def _watch_jql(base_jql: str, since: datetime) -> str:
    created_clause = f'created > "{since.strftime("%Y-%m-%d %H:%M")}"'
    if base_jql:
        return f"({base_jql}) AND {created_clause} ORDER BY created DESC"
    return f"{created_clause} ORDER BY created DESC"


def _strip_order_by(jql: str) -> str:
    return re.split(r"\border\s+by\b", jql, maxsplit=1, flags=re.IGNORECASE)[0].strip()


def _parse_datetime(value: object, timezone: ZoneInfo) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone)
    return parsed.astimezone(timezone)


def _issue_created(issue: dict) -> datetime:
    value = str(issue.get("fields", {}).get("created", ""))
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)


def _trim_seen_keys(values: list[object]) -> list[str]:
    output: list[str] = []
    for value in values:
        key = str(value).strip()
        if key and key not in output:
            output.append(key)
    return output[:300]


def _format_issues(config: AppConfig, issues: list[dict]) -> str:
    lines = [f"새로 등록된 Jira 일감 {len(issues)}개"]
    for issue in issues:
        fields = issue.get("fields", {})
        key = issue.get("key", "")
        summary = fields.get("summary", "제목 없음")
        issue_type = (fields.get("issuetype") or {}).get("name", "-")
        priority = (fields.get("priority") or {}).get("name", "-")
        reporter = (fields.get("reporter") or {}).get("displayName", "-")
        assignee = (fields.get("assignee") or {}).get("displayName", "미할당")
        created = _issue_created(issue)
        created_text = created.astimezone(ZoneInfo(config.general.timezone)).strftime("%H:%M") if created.year > 1 else "-"
        url = f"{config.jira.base_url}/browse/{key}" if config.jira.base_url and key else ""
        lines.append(f"- [{key}] {summary}")
        lines.append(f"  유형: {issue_type} | 우선순위: {priority} | 담당: {assignee} | 등록: {created_text} | 보고자: {reporter}")
        if url:
            lines.append(f"  링크: {url}")
    return "\n".join(lines)

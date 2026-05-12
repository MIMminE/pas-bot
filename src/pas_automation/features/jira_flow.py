from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.jira import JiraClient


def team_flow(config: AppConfig, *, days: int = 7, max_results: int = 80, output_format: str = "text") -> str:
    if not config.features.jira:
        return "Jira 기능이 꺼져 있습니다."

    project = config.jira.default_project.strip()
    since = datetime.now(ZoneInfo(config.general.timezone)) - timedelta(days=max(days, 1))
    date_clause = since.strftime("%Y-%m-%d")
    if project:
        jql = f'project = {project} AND updated >= "{date_clause}" ORDER BY updated DESC'
    else:
        jql = f'updated >= "{date_clause}" ORDER BY updated DESC'

    issues = JiraClient(config.jira).search(jql, max_results=max_results)
    rows = [_flow_row(config, issue) for issue in issues]
    if output_format == "tsv":
        return "\n".join("\t".join(row) for row in rows)

    status_counts = Counter(row[2] for row in rows)
    assignee_counts = Counter(row[3] for row in rows)
    lines = [f"팀 Jira 흐름 - 최근 {days}일", f"조회 일감: {len(rows)}개"]
    if status_counts:
        lines.append("상태 흐름: " + ", ".join(f"{name} {count}개" for name, count in status_counts.most_common()))
    if assignee_counts:
        lines.append("담당 흐름: " + ", ".join(f"{name} {count}개" for name, count in assignee_counts.most_common(8)))
    lines.append("")
    for row in rows[:20]:
        key, summary, status, reporter, assignee, created, updated, due, issue_type, project, url = row
        lines.append(f"- [{key}] {summary}")
        lines.append(f"  상태: {status} | 등록자: {reporter} | 담당: {assignee} | 등록: {created} | 갱신: {updated} | 마감: {due}")
        if url:
            lines.append(f"  링크: {url}")
    return "\n".join(lines)


def _flow_row(config: AppConfig, issue: dict[str, Any]) -> list[str]:
    fields = issue.get("fields", {}) or {}
    key = str(issue.get("key", ""))
    summary = str(fields.get("summary", "제목 없음")).replace("\t", " ").replace("\n", " ")
    status = ((fields.get("status") or {}).get("name") or "Unknown").replace("\t", " ")
    reporter = ((fields.get("reporter") or {}).get("displayName") or "-").replace("\t", " ")
    assignee = ((fields.get("assignee") or {}).get("displayName") or "미할당").replace("\t", " ")
    created = _format_datetime(fields.get("created"), config.general.timezone)
    updated = _format_datetime(fields.get("updated"), config.general.timezone)
    due = str(fields.get("duedate") or "-")
    issue_type = ((fields.get("issuetype") or {}).get("name") or "-").replace("\t", " ")
    project = ((fields.get("project") or {}).get("key") or "-").replace("\t", " ")
    url = f"{config.jira.base_url}/browse/{key}" if config.jira.base_url and key else ""
    return [key, summary, status, reporter, assignee, created, updated, due, issue_type, project, url]


def _format_datetime(value: object, timezone: str) -> str:
    if not isinstance(value, str) or not value.strip():
        return "-"
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return "-"
    return parsed.astimezone(ZoneInfo(timezone)).strftime("%m-%d %H:%M")

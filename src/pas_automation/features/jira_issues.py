from __future__ import annotations

from pas_automation.config import AppConfig
from pas_automation.integrations.jira import JiraClient


def create_issue(
    config: AppConfig,
    *,
    summary: str,
    description: str = "",
    issue_type: str = "Task",
    assignee: str = "",
    priority: str = "",
    due_date: str = "",
    labels: list[str] | None = None,
    project_key: str = "",
    dry_run: bool = False,
) -> str:
    summary = summary.strip()
    if not summary:
        raise RuntimeError("Jira 일감 제목이 필요합니다.")

    project = (project_key or config.jira.default_project).strip()
    if not project:
        raise RuntimeError("Jira project key가 필요합니다.")

    cleaned_labels = [item.strip() for item in labels or [] if item.strip()]
    if dry_run:
        return "\n".join(
            [
                "[dry-run] Jira 일감 생성",
                f"- project: {project}",
                f"- type: {issue_type or 'Task'}",
                f"- summary: {summary}",
                f"- assignee: {assignee or '-'}",
                f"- priority: {priority or '-'}",
                f"- due: {due_date or '-'}",
                f"- labels: {', '.join(cleaned_labels) if cleaned_labels else '-'}",
            ]
        )

    client = JiraClient(config.jira)
    payload = client.create_issue(
        project_key=project,
        summary=summary,
        issue_type=issue_type or "Task",
        description=description.strip(),
        assignee=assignee.strip(),
        priority=priority.strip(),
        due_date=due_date.strip(),
        labels=cleaned_labels,
    )
    key = str(payload.get("key") or "")
    if not key:
        return f"Jira 일감을 생성했습니다.\n{payload}"
    return "\n".join(
        [
            "Jira 일감을 생성했습니다.",
            f"- key: {key}",
            f"- url: {config.jira.base_url}/browse/{key}",
        ]
    )

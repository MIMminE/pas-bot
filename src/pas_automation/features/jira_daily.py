from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from urllib.parse import urlencode
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.features.assignees import resolve_assignee
from pas_automation.features.issue_repositories import IssueRepositoryLink, issue_repository_links
from pas_automation.integrations.git_repos import configured_repositories, git
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.slack import (
    SlackClient,
    actions_block,
    button_element,
    context_block,
    divider_block,
    fields_block,
    header_block,
    section_block,
)


@dataclass(frozen=True)
class LocalBranchMatch:
    repository: str
    branch: str
    path: str


def format_today_items(
    config: AppConfig,
    *,
    max_results: int = 25,
    dry_run: bool = False,
    send_slack: bool = False,
) -> str:
    if not config.features.jira_daily:
        return "Jira 일일 브리핑 기능이 꺼져 있습니다."
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
    raw_issues = client.search(config.jira.todo_jql, max_results=max_results)
    issues = _without_nested_subtasks(raw_issues)
    yesterday_keys = _issue_keys(client.search(config.jira.yesterday_assigned_jql, max_results=100))
    stale_keys = _issue_keys(client.search(config.jira.stale_jql, max_results=100))
    high_keys = _issue_keys(client.search(config.jira.high_priority_jql, max_results=100))
    branch_matches = _local_branch_matches(config, issues)
    repo_links = issue_repository_links()

    today = datetime.now(ZoneInfo(config.general.timezone)).date().isoformat()
    lines = _build_text_report(config, today, issues, yesterday_keys, stale_keys, high_keys, branch_matches, repo_links)

    message = "\n".join(lines)
    if send_slack:
        SlackClient(config.slack, destination="jira_daily").send(
            message,
            blocks=_build_slack_blocks(config, today, issues, yesterday_keys, stale_keys, high_keys, branch_matches, repo_links),
        )
    return message


def today_items_slack_blocks(config: AppConfig, *, max_results: int = 10) -> list[dict[str, Any]]:
    client = JiraClient(config.jira)
    raw_issues = client.search(config.jira.todo_jql, max_results=max_results)
    issues = _without_nested_subtasks(raw_issues)
    yesterday_keys = _issue_keys(client.search(config.jira.yesterday_assigned_jql, max_results=100))
    stale_keys = _issue_keys(client.search(config.jira.stale_jql, max_results=100))
    high_keys = _issue_keys(client.search(config.jira.high_priority_jql, max_results=100))
    branch_matches = _local_branch_matches(config, issues)
    repo_links = issue_repository_links()
    today = datetime.now(ZoneInfo(config.general.timezone)).date().isoformat()
    return _build_slack_blocks(config, today, issues, yesterday_keys, stale_keys, high_keys, branch_matches, repo_links)


def assign_issue(config: AppConfig, issue_key: str, account_id_or_email: str, *, dry_run: bool) -> str:
    account_id_or_email = resolve_assignee(config, account_id_or_email)
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
    branch_matches: dict[str, list[LocalBranchMatch]],
    repo_links: dict[str, IssueRepositoryLink],
) -> list[str]:
    subtask_count = sum(len(_subtasks(issue)) for issue in issues)
    lines = [
        f"오늘의 Jira 일감 - {today}",
        (
            "오늘의 Jira 일감: "
            f"미처리 {len(issues)}개, "
            f"하위 일감 {subtask_count}개, "
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
            lines.extend(_format_issue(config, issue, yesterday_keys, stale_keys, high_keys, branch_matches, repo_links))
    return lines


def _build_slack_blocks(
    config: AppConfig,
    today: str,
    issues: list[dict[str, Any]],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
    branch_matches: dict[str, list[LocalBranchMatch]],
    repo_links: dict[str, IssueRepositoryLink],
) -> list[dict[str, Any]]:
    subtask_count = sum(len(_subtasks(issue)) for issue in issues)
    blocks = [
        header_block(f"오늘의 Jira 일감"),
        fields_block(
            [
                f"*미처리*\n*{len(issues)}개*",
                f"*하위 일감*\n{subtask_count}개",
                f"*어제 할당*\n{len(yesterday_keys)}개",
                f"*5일 이상 미갱신*\n{len(stale_keys)}개",
                f"*높은 우선순위*\n{len(high_keys)}개",
            ]
        ),
        context_block(f"기준일 {today} · 우선순위/미갱신/브랜치 연결 상태를 함께 표시합니다."),
        divider_block(),
    ]

    if not issues:
        blocks.append(section_block("확인할 미처리 일감이 없습니다."))
        return blocks

    for index, issue in enumerate(issues[:10], start=1):
        blocks.append(section_block(_format_issue_card_markdown(config, issue, index, yesterday_keys, stale_keys, high_keys, branch_matches, repo_links)))
        summary_text = _format_issue_summary_markdown(issue)
        if summary_text:
            blocks.append(section_block(summary_text))
        subtask_text = _format_subtasks_markdown(config, issue)
        if subtask_text:
            blocks.append(context_block(subtask_text))
        branch_text = _format_branches_markdown(issue, branch_matches)
        if branch_text:
            blocks.append(context_block(branch_text))
        repo_link_text = _format_issue_repo_link_markdown(issue, repo_links)
        if repo_link_text:
            blocks.append(context_block(repo_link_text))
        issue_actions = _format_issue_actions_markdown(issue, repo_links)
        if issue_actions:
            blocks.append(actions_block(_issue_action_buttons(config, issue, repo_links)))
            blocks.append(context_block(issue_actions))
        blocks.append(divider_block())

    if len(issues) > 10:
        blocks.append(context_block(f"Slack 표시 한도 때문에 상위 10개만 표시했습니다. 전체 조회 결과: {len(issues)}개"))

    return blocks[:50]


def _format_issue_card_markdown(
    config: AppConfig,
    issue: dict[str, Any],
    index: int,
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
    branch_matches: dict[str, list[LocalBranchMatch]],
    repo_links: dict[str, IssueRepositoryLink],
) -> str:
    fields = issue["fields"]
    priority = (fields.get("priority", {}) or {}).get("name", "-")
    status = (fields.get("status", {}) or {}).get("name", "Unknown")
    due = fields.get("duedate") or "-"
    badges = _badges(issue["key"], yesterday_keys, stale_keys, high_keys)
    badge_text = " ".join(f"`{badge}`" for badge in badges)
    branch_count = len(branch_matches.get(issue["key"], []))
    repo_text = repo_links[issue["key"]].repo_name if issue["key"] in repo_links else "미선택"
    return "\n".join(
        [
            f"*{index}. <{_issue_url(config, issue['key'])}|{issue['key']}> · {fields.get('summary', '')}*",
            f"{badge_text}".strip(),
            f"`{status}` · `{priority}` · 마감 `{due}` · 하위 `{len(_subtasks(issue))}` · 브랜치 `{branch_count}` · repo `{repo_text}`",
        ]
    ).strip()


def _format_issue(
    config: AppConfig,
    issue: dict[str, Any],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
    branch_matches: dict[str, list[LocalBranchMatch]],
    repo_links: dict[str, IssueRepositoryLink],
) -> list[str]:
    fields = issue["fields"]
    priority = fields.get("priority", {}) or {}
    status = fields.get("status", {}) or {}
    due = fields.get("duedate") or "-"
    badges = _badges(issue["key"], yesterday_keys, stale_keys, high_keys)
    badge_text = "".join(f" [{badge}]" for badge in badges)
    description = _truncate(_description_to_text(fields.get("description")), 220)
    lines = [
        "",
        f"{issue['key']}{badge_text} {fields.get('summary', '')}",
        f"상태: {status.get('name', 'Unknown')} | 우선순위: {priority.get('name', '-')} | 마감: {due}",
        f"링크: {_issue_url(config, issue['key'])}",
        f"내용: {description}",
    ]
    subtasks = _subtasks(issue)
    if subtasks:
        lines.append(f"하위 일감: {len(subtasks)}개")
        for subtask in subtasks[:5]:
            lines.append(f"  - {_format_subtask_text(config, subtask)}")
        if len(subtasks) > 5:
            lines.append(f"  - 외 {len(subtasks) - 5}개")
    branches = branch_matches.get(issue["key"], [])
    if branches:
        lines.append(f"관련 로컬 브랜치: {len(branches)}개")
        for branch in branches[:5]:
            lines.append(f"  - {branch.repository}: {branch.branch} | {branch.path}")
    repo_link = repo_links.get(issue["key"])
    if repo_link:
        lines.append(f"연결 repository: {repo_link.repo_name} | {repo_link.repo_path}")
    else:
        lines.append("연결 repository: 미선택")
    return lines


def _format_issue_markdown(
    config: AppConfig,
    issue: dict[str, Any],
    yesterday_keys: set[str],
    stale_keys: set[str],
    high_keys: set[str],
    branch_matches: dict[str, list[LocalBranchMatch]],
    repo_links: dict[str, IssueRepositoryLink],
) -> str:
    fields = issue["fields"]
    badges = " ".join(f"`{badge}`" for badge in _badges(issue["key"], yesterday_keys, stale_keys, high_keys))
    subtask_badge = f"`하위 {len(_subtasks(issue))}`" if _subtasks(issue) else ""
    branch_badge = f"`브랜치 {len(branch_matches.get(issue['key'], []))}`" if branch_matches.get(issue["key"]) else ""
    repo_badge = f"`repo {repo_links[issue['key']].repo_name}`" if issue["key"] in repo_links else "`repo 미선택`"
    title = f"<{_issue_url(config, issue['key'])}|{issue['key']}> {fields.get('summary', '')}"
    suffix_parts = [item for item in [badges, subtask_badge, branch_badge, repo_badge] if item]
    suffix = f" {' '.join(suffix_parts)}" if suffix_parts else ""
    return f"*{title}*{suffix}"


def _format_issue_meta_markdown(issue: dict[str, Any]) -> str:
    fields = issue["fields"]
    priority = fields.get("priority", {}) or {}
    status = fields.get("status", {}) or {}
    due = fields.get("duedate") or "-"
    return (
        f"*상태* `{status.get('name', 'Unknown')}`   "
        f"*우선순위* `{priority.get('name', '-')}`   "
        f"*마감일자* `{due}`"
    )


def _format_issue_summary_markdown(issue: dict[str, Any]) -> str:
    description = _truncate(_description_to_text(issue["fields"].get("description")), 180)
    if not description or description == "-":
        return ""
    return f"> {description}"


def _format_subtasks_markdown(config: AppConfig, issue: dict[str, Any]) -> str:
    subtasks = _subtasks(issue)
    if not subtasks:
        return ""
    lines = [f"하위 일감 {len(subtasks)}개"]
    for subtask in subtasks[:5]:
        lines.append(f"• {_format_subtask_markdown(config, subtask)}")
    if len(subtasks) > 5:
        lines.append(f"• 외 {len(subtasks) - 5}개")
    return "\n".join(lines)


def _format_branches_markdown(issue: dict[str, Any], branch_matches: dict[str, list[LocalBranchMatch]]) -> str:
    branches = branch_matches.get(issue["key"], [])
    if not branches:
        return ""
    lines = [f"관련 로컬 브랜치 {len(branches)}개"]
    for branch in branches[:5]:
        lines.append(f"• {branch.repository}: `{branch.branch}`")
    if len(branches) > 5:
        lines.append(f"• 외 {len(branches) - 5}개")
    return "\n".join(lines)


def _format_issue_actions_markdown(issue: dict[str, Any], repo_links: dict[str, IssueRepositoryLink]) -> str:
    issue_key = issue["key"]
    summary = str((issue.get("fields", {}) or {}).get("summary", ""))
    links = [
        _slack_link(
            f"pas://jira/link?{urlencode({'issue': issue_key, 'summary': summary})}",
            "레포 연결 선택",
        )
    ]
    repo_link = repo_links.get(issue_key)
    if repo_link:
        query = urlencode(
            {
                "issue": issue_key,
                "summary": summary,
                "repo": str(repo_link.repo_path),
            }
        )
        links.append(
            _slack_link(
                f"pas://branch/create?{query}",
                f"{repo_link.repo_name} dev에서 브랜치 시작",
            )
        )
    return "작업: " + " · ".join(links)


def _issue_action_buttons(config: AppConfig, issue: dict[str, Any], repo_links: dict[str, IssueRepositoryLink]) -> list[dict[str, Any]]:
    issue_key = issue["key"]
    return [
        button_element("Jira 열기", _issue_url(config, issue_key), action_id=f"open_{issue_key}"),
    ]


def _slack_link(url: str, label: str) -> str:
    return f"<{url}|{label}>"


def _format_issue_repo_link_markdown(issue: dict[str, Any], repo_links: dict[str, IssueRepositoryLink]) -> str:
    repo_link = repo_links.get(issue["key"])
    if not repo_link:
        return "연결 repository: 아직 선택하지 않았습니다."
    return f"연결 repository: *{repo_link.repo_name}* `{repo_link.repo_path}`"


def _local_branch_matches(config: AppConfig, issues: list[dict[str, Any]]) -> dict[str, list[LocalBranchMatch]]:
    repos = configured_repositories(config)
    if not repos:
        return {}

    matches: dict[str, list[LocalBranchMatch]] = {}
    for issue in issues:
        issue_key = issue["key"]
        found: list[LocalBranchMatch] = []
        needle = issue_key.lower()
        for repo in repos:
            try:
                output = git(repo, "branch", "-a", "--format=%(refname:short)")
            except RuntimeError:
                continue
            for branch in output.splitlines():
                name = branch.strip()
                if not name or "HEAD ->" in name:
                    continue
                if needle in name.lower():
                    found.append(LocalBranchMatch(repository=repo.name, branch=name, path=str(repo)))
                    if len(found) >= 5:
                        break
            if len(found) >= 5:
                break
        if found:
            matches[issue_key] = found
    return matches


def _format_subtask_markdown(config: AppConfig, subtask: dict[str, Any]) -> str:
    fields = subtask.get("fields", {}) or {}
    status = fields.get("status", {}) or {}
    summary = fields.get("summary", "")
    key = subtask.get("key", "")
    return f"<{_issue_url(config, key)}|{key}> {summary} - {status.get('name', 'Unknown')}"


def _format_subtask_text(config: AppConfig, subtask: dict[str, Any]) -> str:
    fields = subtask.get("fields", {}) or {}
    status = fields.get("status", {}) or {}
    summary = fields.get("summary", "")
    key = subtask.get("key", "")
    return f"{key} {summary} | 상태: {status.get('name', 'Unknown')} | 링크: {_issue_url(config, key)}"


def _subtasks(issue: dict[str, Any]) -> list[dict[str, Any]]:
    return list((issue.get("fields", {}) or {}).get("subtasks") or [])


def _without_nested_subtasks(issues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    nested_keys = {subtask.get("key") for issue in issues for subtask in _subtasks(issue)}
    return [issue for issue in issues if issue.get("key") not in nested_keys]


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

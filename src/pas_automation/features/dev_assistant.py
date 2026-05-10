from __future__ import annotations

import re
from pathlib import Path

from pas_automation.config import AppConfig
from pas_automation.features.jira_daily import format_today_items
from pas_automation.features.repo_report import report
from pas_automation.features.repo_status import collect_repo_status, format_repo_status
from pas_automation.integrations.git_repos import changed_files, current_branch, discover_repositories, recent_commits, staged_files
from pas_automation.integrations.github import GitHubClient
from pas_automation.integrations.slack import SlackWebhook, context_block, divider_block, header_block, section_block


ISSUE_KEY_PATTERN = re.compile(r"[A-Z][A-Z0-9]+-\d+")


def morning_briefing(config: AppConfig, *, send_slack: bool, dry_run: bool = False) -> str:
    if not config.features.morning_briefing:
        return "출근 브리핑 기능이 꺼져 있습니다."

    sections = [
        "출근 브리핑",
        "",
        "[오늘 Jira 일감]",
        format_today_items(config, max_results=10, dry_run=dry_run, send_slack=False),
        "",
        "[미처리 PR]",
        _format_open_prs(config, dry_run=dry_run),
        "",
        "[캘린더]",
        "캘린더 연동 미설정: Google/Outlook 연결 추가 예정",
    ]
    message = "\n".join(sections)
    if send_slack and not dry_run:
        SlackWebhook(config.slack, destination="morning_briefing").send(message, blocks=_routine_blocks("출근 브리핑", message))
    return message


def evening_check(config: AppConfig, *, send_slack: bool, dry_run: bool = False) -> str:
    if not config.features.evening_check:
        return "퇴근 체크 기능이 꺼져 있습니다."

    statuses = collect_repo_status(config)
    sections = [
        "퇴근 체크",
        "",
        "[로컬 repository 상태]",
        format_repo_status(statuses),
        "",
        "[오늘 작업 보고]",
        _safe_git_report(config, dry_run=dry_run),
        "",
        "[Jira 키 누락 점검]",
        audit_jira_keys(config),
    ]
    message = "\n".join(sections)
    if send_slack and not dry_run:
        SlackWebhook(config.slack, destination="evening_check").send(message, blocks=_routine_blocks("퇴근 체크", message))
    return message


def branch_name(issue_key: str, summary: str, *, prefix: str = "feature") -> str:
    return f"{prefix}/{issue_key.upper()}-{_slug(summary)}"


def commit_message(config: AppConfig, repo_path: str | None, issue_key: str | None) -> str:
    _ensure_dev_tools(config)
    repo = _repo_path(config, repo_path)
    files = staged_files(repo) or changed_files(repo)
    scope = _common_scope(files)
    key = issue_key or _issue_key_from_text(current_branch(repo)) or config.jira.default_project
    subject = f"{key} {scope} 변경"
    body = "\n".join(f"- {item}" for item in files[:8]) if files else "- 변경 파일 없음"
    return f"{subject}\n\n{body}"


def pr_draft(config: AppConfig, repo_path: str | None, issue_key: str | None) -> str:
    _ensure_dev_tools(config)
    repo = _repo_path(config, repo_path)
    branch = current_branch(repo)
    key = issue_key or _issue_key_from_text(branch) or config.jira.default_project
    commits = recent_commits(repo, author=config.general.git_author, max_count=10)
    title = f"{key} {branch.replace('-', ' ')}"
    lines = [
        title,
        "",
        "## 작업 내용",
        *[f"- {line}" for line in commits[:8]],
        "",
        "## 확인 필요",
        "- 테스트/동작 확인",
        "- Jira 일감 링크 확인",
    ]
    return "\n".join(lines)


def audit_jira_keys(config: AppConfig) -> str:
    _ensure_dev_tools(config)
    rows: list[str] = []
    for repo in _repositories(config):
        branch = current_branch(repo)
        missing_branch_key = not _issue_key_from_text(branch)
        missing_commit_keys = [line for line in recent_commits(repo, max_count=5) if not _issue_key_from_text(line)]
        if missing_branch_key or missing_commit_keys:
            rows.append(f"- {repo.name} [{branch}]")
            if missing_branch_key:
                rows.append("  - 브랜치명에 Jira 키 없음")
            for commit in missing_commit_keys[:3]:
                rows.append(f"  - 커밋 Jira 키 없음: {commit}")
    return "\n".join(rows) if rows else "Jira 키 누락 항목 없음"


def dashboard(config: AppConfig) -> str:
    _ensure_dev_tools(config)
    return format_repo_status(collect_repo_status(config))


def _ensure_dev_tools(config: AppConfig) -> None:
    if not config.features.dev_tools:
        raise RuntimeError("개발자 루틴 보조 기능이 꺼져 있습니다.")


def _format_open_prs(config: AppConfig, *, dry_run: bool = False) -> str:
    if dry_run:
        return "[dry-run] GitHub 미처리 PR 조회"
    if not config.github.repositories:
        return "GitHub repository 설정 없음"
    try:
        prs = GitHubClient(config.github).open_pull_requests(max_per_repo=10)
    except RuntimeError as exc:
        return f"GitHub PR 조회 실패: {exc}"
    if not prs:
        return "미처리 PR 없음"
    return "\n".join(f"- {pr.repository} #{pr.number} {pr.title} ({'draft' if pr.draft else pr.state}) {pr.url}" for pr in prs)


def _safe_git_report(config: AppConfig, *, dry_run: bool) -> str:
    try:
        return report(config, snapshot_name="morning", send_slack=False, dry_run=dry_run)
    except RuntimeError as exc:
        return f"Git 보고서 생성 보류: {exc}"


def _routine_blocks(title: str, message: str) -> list[dict]:
    chunks = [chunk.strip() for chunk in message.split("\n\n") if chunk.strip()]
    blocks = [header_block(title)]
    for chunk in chunks[:12]:
        blocks.append(section_block(chunk))
        blocks.append(divider_block())
    blocks.append(context_block("PAS 개발자 루틴 보조"))
    return blocks[:50]


def _repositories(config: AppConfig) -> list[Path]:
    repos: list[Path] = []
    for root in config.repo_roots:
        repos.extend(discover_repositories(root.path, recursive=root.recursive))
    return repos


def _repo_path(config: AppConfig, repo_path: str | None) -> Path:
    if repo_path:
        return Path(repo_path).expanduser()
    repos = _repositories(config)
    if not repos:
        raise RuntimeError("설정된 repository root에서 Git repository를 찾지 못했습니다.")
    return repos[0]


def _issue_key_from_text(text: str) -> str | None:
    match = ISSUE_KEY_PATTERN.search(text.upper())
    return match.group(0) if match else None


def _slug(value: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9가-힣]+", "-", value.strip().lower()).strip("-")
    return normalized[:48] or "work"


def _common_scope(files: list[str]) -> str:
    if not files:
        return "작업"
    first = files[0].split("/", 1)[0].split("\\", 1)[0]
    return first or "작업"

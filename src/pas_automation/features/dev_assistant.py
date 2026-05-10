from __future__ import annotations

import re
from pathlib import Path

from pas_automation.config import AppConfig
from pas_automation.features.jira_daily import format_today_items
from pas_automation.features.repo_report import report
from pas_automation.features.repo_status import collect_repo_status, format_repo_status
from pas_automation.integrations.calendar import format_calendar, upcoming_events
from pas_automation.integrations.git_repos import (
    changed_files,
    configured_repositories,
    current_branch,
    fetch,
    git,
    pull_ff_only,
    recent_commits,
    require_clean_worktree,
    staged_files,
)
from pas_automation.integrations.slack import SlackClient, context_block, divider_block, header_block, section_block


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
        "[로컬 Git 상태]",
        format_repo_status(collect_repo_status(config)),
        "",
        "[캘린더]",
        calendar_summary(config),
    ]
    message = "\n".join(sections)
    if send_slack and not dry_run:
        SlackClient(config.slack, destination="morning_briefing").send(message, blocks=_routine_blocks("출근 브리핑", message))
    return message


def evening_check(config: AppConfig, *, send_slack: bool, dry_run: bool = False) -> str:
    if not config.features.evening_check:
        return "퇴근 체크 기능이 꺼져 있습니다."

    from pas_automation.features.dev_insights import evening_checklist

    statuses = collect_repo_status(config)
    sections = [
        "퇴근 체크",
        "",
        "[퇴근 전 체크리스트]",
        evening_checklist(config),
        "",
        "[관리 repository 상태]",
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
        SlackClient(config.slack, destination="evening_check").send(message, blocks=_routine_blocks("퇴근 체크", message))
    return message


def branch_name(issue_key: str, summary: str, *, prefix: str = "feature") -> str:
    return f"{prefix}/{issue_key.upper()}-{_slug(summary)}"


def create_branch(
    config: AppConfig,
    repo_path: str,
    issue_key: str,
    summary: str,
    *,
    prefix: str = "feature",
    base_branch: str = "dev",
) -> str:
    _ensure_dev_tools(config)
    repo = Path(repo_path).expanduser().resolve()
    managed = {item.expanduser().resolve() for item in configured_repositories(config)}
    if repo not in managed:
        raise RuntimeError(f"관리 대상 repository가 아닙니다: {repo}")
    if not (repo / ".git").is_dir():
        raise RuntimeError(f"Git repository를 찾지 못했습니다: {repo}")

    require_clean_worktree(repo, action="브랜치 생성")
    name = branch_name(issue_key, summary, prefix=prefix)
    existed = _local_branch_exists(repo, name)
    if existed:
        output = git(repo, "checkout", name)
        details = output.strip()
        suffix = f"\n{details}" if details else ""
        return f"{repo.name}: 기존 작업 브랜치로 이동\n- 브랜치: {name}{suffix}"

    base = _prepare_latest_base_branch(repo, base_branch=base_branch)
    output = git(repo, "checkout", "-b", name)
    details = output.strip()
    suffix = f"\n{details}" if details else ""
    return "\n".join(
        [
            f"{repo.name}: Jira 작업 브랜치 생성 완료",
            f"- 기준 브랜치: {base}",
            f"- 작업 브랜치: {name}",
            f"- Jira 키: {issue_key.upper()}",
        ]
    ) + suffix


def _prepare_latest_base_branch(repo: Path, *, base_branch: str) -> str:
    fetch(repo)
    candidates = _base_branch_candidates(base_branch)
    for candidate in candidates:
        remote = f"origin/{candidate}"
        if _local_branch_exists(repo, candidate):
            git(repo, "checkout", candidate)
            if _remote_branch_exists(repo, remote):
                git(repo, "merge", "--ff-only", remote)
            else:
                pull_ff_only(repo)
            return candidate
        if _remote_branch_exists(repo, remote):
            git(repo, "checkout", "-b", candidate, "--track", remote)
            pull_ff_only(repo)
            return candidate
    raise RuntimeError(
        "\n".join(
            [
                "작업 브랜치를 시작할 기준 브랜치를 찾지 못했습니다.",
                f"확인한 후보: {', '.join(candidates)}",
                "레포에 dev/develop 계열 브랜치가 있는지 확인해 주세요.",
            ]
        )
    )


def _base_branch_candidates(base_branch: str) -> list[str]:
    values = [base_branch.strip(), "dev", "develop", "development", "main", "master"]
    seen: set[str] = set()
    candidates: list[str] = []
    for item in values:
        if not item or item in seen:
            continue
        seen.add(item)
        candidates.append(item)
    return candidates


def _remote_branch_exists(repo: Path, name: str) -> bool:
    try:
        git(repo, "show-ref", "--verify", "--quiet", f"refs/remotes/{name}")
    except RuntimeError:
        return False
    return True


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
    return "\n\n".join(
        [
            "PAS 통합 대시보드",
            "[캘린더]",
            calendar_summary(config),
            "[로컬 Git 상태]",
            format_repo_status(collect_repo_status(config)),
        ]
    )


def calendar_summary(config: AppConfig) -> str:
    if not config.calendar.enabled:
        return "캘린더 기능 꺼짐: [calendar].enabled = true 설정 필요"
    if not config.calendar.sources:
        return "캘린더 소스 없음: [[calendar.sources]]에 iCal URL 또는 .ics 파일 경로 입력"
    try:
        return format_calendar(upcoming_events(config.calendar, timezone=config.general.timezone))
    except Exception as exc:
        return f"캘린더 조회 실패: {exc}"


def _ensure_dev_tools(config: AppConfig) -> None:
    if not config.features.dev_tools:
        raise RuntimeError("개발자 루틴 보조 기능이 꺼져 있습니다.")


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
    return configured_repositories(config)


def _repo_path(config: AppConfig, repo_path: str | None) -> Path:
    if repo_path:
        return Path(repo_path).expanduser()
    repos = _repositories(config)
    if not repos:
        raise RuntimeError("관리 대상으로 등록된 Git repository가 없습니다. 설정에서 gh CLI 후보를 가져와 등록해 주세요.")
    return repos[0]


def _issue_key_from_text(text: str) -> str | None:
    match = ISSUE_KEY_PATTERN.search(text.upper())
    return match.group(0) if match else None


def _local_branch_exists(repo: Path, name: str) -> bool:
    try:
        git(repo, "show-ref", "--verify", "--quiet", f"refs/heads/{name}")
    except RuntimeError:
        return False
    return True


def _slug(value: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9가-힣]+", "-", value.strip().lower()).strip("-")
    return normalized[:48] or "work"


def _common_scope(files: list[str]) -> str:
    if not files:
        return "작업"
    first = files[0].split("/", 1)[0].split("\\", 1)[0]
    return first or "작업"

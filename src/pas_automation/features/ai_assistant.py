from __future__ import annotations

from datetime import date, datetime
import calendar
import json
from pathlib import Path

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import current_branch, discover_repositories, git, recent_commits
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.openai_report import generate_text, tone_instruction


def git_summary(config: AppConfig, *, tone: str = "brief", days: int = 1) -> str:
    commits = _recent_commit_context(config, days=days)
    return generate_text(
        config.openai,
        system=_system(tone),
        prompt=(
            f"아래 Git 커밋을 기반으로 오늘 한 일을 한국어로 요약해줘.\n"
            "섹션: 핵심 작업, 확인한 내용, 남은 리스크.\n\n"
            f"{commits}"
        ),
        fallback=_fallback("Git 커밋 기반 오늘 한 일 요약", commits),
    )


def pr_description(config: AppConfig, *, repo_path: str | None, issue_key: str | None, tone: str = "brief") -> str:
    repo = _repo_path(config, repo_path)
    commits = "\n".join(recent_commits(repo, author=config.general.git_author, max_count=15))
    branch = current_branch(repo)
    issue = _jira_issue_context(config, issue_key) if issue_key else ""
    return generate_text(
        config.openai,
        system=_system(tone),
        prompt=(
            "아래 정보를 기반으로 GitHub PR 제목과 본문 초안을 작성해줘.\n"
            "본문 섹션: 작업 내용, 확인 방법, 리스크/참고.\n\n"
            f"브랜치: {branch}\n"
            f"Jira:\n{issue}\n\n"
            f"커밋:\n{commits}"
        ),
        fallback=_fallback("PR 설명 초안", f"브랜치: {branch}\n\n{issue}\n\n{commits}"),
    )


def jira_issue_summary(config: AppConfig, *, issue_key: str, tone: str = "brief") -> str:
    context = _jira_issue_context(config, issue_key)
    return generate_text(
        config.openai,
        system=_system(tone),
        prompt=(
            "아래 Jira 이슈 내용을 한국어로 정리해줘.\n"
            "섹션: 한 줄 요약, 요구사항, 확인 포인트, 예상 작업.\n\n"
            f"{context}"
        ),
        fallback=_fallback("Jira 이슈 내용 정리", context),
    )


def monthly_review(config: AppConfig, *, month: str, tone: str = "manager") -> str:
    start, end = _month_range(month)
    commits = _commit_context_between(config, start=start, end=end)
    return generate_text(
        config.openai,
        system=_system(tone),
        prompt=(
            f"{month} 월간 회고 초안을 작성해줘.\n"
            "섹션: 주요 성과, 반복 작업/개선, 리스크, 다음 달 액션.\n\n"
            f"{commits}"
        ),
        fallback=_fallback(f"{month} 월간 회고 초안", commits),
    )


def incident_draft(config: AppConfig, *, issue_key: str | None, notes: str, tone: str = "detailed") -> str:
    issue = _jira_issue_context(config, issue_key) if issue_key else ""
    return generate_text(
        config.openai,
        system=_system(tone),
        prompt=(
            "아래 정보를 기반으로 장애/버그 이슈 원인 정리 초안을 작성해줘.\n"
            "단정하지 말고 확인된 사실과 추정 사항을 구분해줘.\n"
            "섹션: 현상, 영향 범위, 원인 후보, 확인 근거, 조치/재발 방지.\n\n"
            f"Jira:\n{issue}\n\n"
            f"메모:\n{notes}"
        ),
        fallback=_fallback("장애/버그 이슈 원인 정리 초안", f"{issue}\n\n{notes}"),
    )


def _system(tone: str) -> str:
    return (
        "You are a Korean developer assistant. "
        "Write practical engineering reports without exaggeration. "
        "Separate facts from assumptions. "
        f"Tone: {tone_instruction(tone)}"
    )


def _recent_commit_context(config: AppConfig, *, days: int) -> str:
    since = f"{days} days ago"
    sections: list[str] = []
    for repo in _repositories(config):
        output = git(
            repo,
            "log",
            f"--since={since}",
            f"--author={config.general.git_author}",
            "--date=iso",
            "--pretty=format:%h | %ad | %s",
        )
        if output:
            sections.append(f"Repository: {repo.name}\n{output}")
    return "\n\n".join(sections)


def _commit_context_between(config: AppConfig, *, start: date, end: date) -> str:
    sections: list[str] = []
    for repo in _repositories(config):
        output = git(
            repo,
            "log",
            f"--since={start.isoformat()} 00:00",
            f"--until={end.isoformat()} 23:59",
            f"--author={config.general.git_author}",
            "--date=short",
            "--pretty=format:%h | %ad | %s",
        )
        if output:
            sections.append(f"Repository: {repo.name}\n{output}")
    return "\n\n".join(sections)


def _jira_issue_context(config: AppConfig, issue_key: str | None) -> str:
    if not issue_key:
        return ""
    issue = JiraClient(config.jira).issue(issue_key)
    fields = issue.get("fields", {}) or {}
    return "\n".join(
        [
            f"Key: {issue.get('key', issue_key)}",
            f"Summary: {fields.get('summary', '')}",
            f"Status: {(fields.get('status') or {}).get('name', '')}",
            f"Priority: {(fields.get('priority') or {}).get('name', '')}",
            f"Description: {_jira_doc_to_text(fields.get('description'))}",
        ]
    )


def _jira_doc_to_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        text = value.get("text")
        if isinstance(text, str):
            return text
        return " ".join(_jira_doc_to_text(item) for item in value.get("content", []) if item)
    if isinstance(value, list):
        return " ".join(_jira_doc_to_text(item) for item in value)
    return json.dumps(value, ensure_ascii=False)


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


def _month_range(value: str) -> tuple[date, date]:
    year_text, month_text = value.split("-", 1)
    year, month = int(year_text), int(month_text)
    last_day = calendar.monthrange(year, month)[1]
    return date(year, month, 1), date(year, month, last_day)


def _fallback(title: str, context: str) -> str:
    if not context.strip():
        return f"{title}\n\n확인된 입력 데이터가 없습니다."
    return f"{title}\n\nAI API 키가 없어 원본 데이터를 정리 없이 표시합니다.\n\n{context}"

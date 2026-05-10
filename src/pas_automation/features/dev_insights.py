from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess

from pas_automation.config import AppConfig
from pas_automation.features.dev_assistant import create_branch
from pas_automation.features.issue_repositories import issue_repository_links, link_issue_repository
from pas_automation.integrations.git_repos import (
    ahead_behind,
    configured_repositories,
    current_branch,
    git,
    owner_repo,
    recent_commits,
    status_porcelain,
)
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.slack import SlackClient, context_block, divider_block, header_block, section_block


ISSUE_KEY_PATTERN = re.compile(r"[A-Z][A-Z0-9]+-\d+")


@dataclass(frozen=True)
class IssueRepoCandidate:
    repo: Path
    score: int
    reasons: list[str]


def recommend_issue_repositories(config: AppConfig, issue_key: str, *, summary: str = "") -> str:
    issue_key = issue_key.upper()
    summary = summary or _safe_issue_summary(config, issue_key)
    links = issue_repository_links()
    candidates: list[IssueRepoCandidate] = []

    for repo in configured_repositories(config):
        score = 0
        reasons: list[str] = []
        if links.get(issue_key) and Path(links[issue_key].repo_path).expanduser().resolve() == repo.resolve():
            score += 100
            reasons.append("이미 연결된 repository")
        branch_count = _count_issue_branches(repo, issue_key)
        if branch_count:
            score += 30 + branch_count
            reasons.append(f"이슈 키 포함 브랜치 {branch_count}개")
        token_hits = _token_hits(repo.name, summary)
        if token_hits:
            score += token_hits * 4
            reasons.append(f"요약 키워드 매칭 {token_hits}개")
        recent_hits = _count_recent_issue_commits(repo, issue_key)
        if recent_hits:
            score += 20 + recent_hits
            reasons.append(f"최근 커밋에 이슈 키 {recent_hits}개")
        if score:
            candidates.append(IssueRepoCandidate(repo=repo, score=score, reasons=reasons))

    if not candidates:
        repos = configured_repositories(config)
        if not repos:
            return "관리 repository가 없습니다. 설정에서 GitHub 후보를 가져와 관리 대상으로 등록해 주세요."
        return "\n".join(
            [
                f"{issue_key} 추천 repository",
                "명확한 추천 근거를 찾지 못했습니다.",
                "관리 repository 중에서 직접 선택해 연결해 주세요.",
                "",
                *[f"- {repo.name} | {repo}" for repo in repos[:12]],
            ]
        )

    candidates.sort(key=lambda item: item.score, reverse=True)
    lines = [f"{issue_key} 추천 repository", f"요약: {summary or '-'}", ""]
    for item in candidates[:8]:
        lines.append(f"- {item.repo.name} 점수 {item.score} | {item.repo}")
        lines.extend(f"  - {reason}" for reason in item.reasons)
    return "\n".join(lines)


def trace_issue_work(config: AppConfig, issue_key: str) -> str:
    issue_key = issue_key.upper()
    lines = [f"{issue_key} 작업 연결 추적", ""]
    links = issue_repository_links()
    if issue_key in links:
        link = links[issue_key]
        lines.append(f"[연결 repository]\n- {link.repo_name} | {link.repo_path}")
        lines.append("")

    found = False
    for repo in configured_repositories(config):
        sections = [
            _repo_section("브랜치", _issue_branches(repo, issue_key)),
            _repo_section("커밋", _issue_commits(repo, issue_key)),
            _repo_section("PR", _issue_pull_requests(repo, issue_key)),
        ]
        rendered = [section for section in sections if section]
        if rendered:
            found = True
            lines.append(f"[{repo.name}]")
            lines.extend(rendered)
            lines.append("")

    if not found and issue_key not in links:
        lines.append("연결된 repository, 브랜치, 커밋, PR을 찾지 못했습니다.")
    return "\n".join(lines).strip()


def pr_status_dashboard(config: AppConfig, *, send_slack: bool = False) -> str:
    lines = ["PR 상태 대시보드", ""]
    count = 0
    for repo in configured_repositories(config):
        prs = _open_pull_requests(repo)
        if not prs:
            continue
        count += len(prs)
        lines.append(f"[{repo.name}]")
        for row in prs[:10]:
            lines.append(
                f"- #{row.get('number')} {row.get('title')} | {row.get('headRefName')} -> {row.get('baseRefName')} | "
                f"{row.get('reviewDecision') or 'REVIEW_UNKNOWN'} | {row.get('url')}"
            )
        lines.append("")
    if count == 0:
        lines.append("열린 PR이 없습니다.")
    message = "\n".join(lines).strip()
    if send_slack:
        _send_dev_alert(config, "PR 상태 대시보드", message)
    return message


def review_request_alerts(config: AppConfig, *, send_slack: bool = False) -> str:
    lines = ["리뷰 요청 알림", ""]
    count = 0
    for repo in configured_repositories(config):
        rows = _gh_json(
            [
                "gh",
                "pr",
                "list",
                "--repo",
                owner_repo(repo),
                "--search",
                "review-requested:@me",
                "--json",
                "number,title,url,author,updatedAt",
                "--limit",
                "20",
            ]
        )
        if not rows:
            continue
        count += len(rows)
        lines.append(f"[{repo.name}]")
        for row in rows:
            author = (row.get("author") or {}).get("login", "")
            lines.append(f"- #{row.get('number')} {row.get('title')} | {author} | {row.get('url')}")
        lines.append("")
    if count == 0:
        lines.append("현재 나에게 요청된 PR 리뷰가 없습니다.")
    message = "\n".join(lines).strip()
    if send_slack and count:
        _send_dev_alert(config, "리뷰 요청 알림", message)
    return message


def ci_failure_alerts(config: AppConfig, *, send_slack: bool = False) -> str:
    lines = ["CI 실패 알림", ""]
    count = 0
    for repo in configured_repositories(config):
        repo_name = owner_repo(repo)
        if not repo_name:
            continue
        rows = _gh_json(
            [
                "gh",
                "run",
                "list",
                "--repo",
                repo_name,
                "--status",
                "failure",
                "--json",
                "name,displayTitle,headBranch,conclusion,url,updatedAt",
                "--limit",
                "10",
            ]
        )
        if not rows:
            continue
        count += len(rows)
        lines.append(f"[{repo.name}]")
        for row in rows[:5]:
            lines.append(f"- {row.get('name')} | {row.get('headBranch')} | {row.get('displayTitle')} | {row.get('url')}")
        lines.append("")
    if count == 0:
        lines.append("최근 실패한 GitHub Actions 실행이 없습니다.")
    message = "\n".join(lines).strip()
    if send_slack and count:
        _send_dev_alert(config, "CI 실패 알림", message)
    return message


def deployment_waiting_issues(config: AppConfig, *, send_slack: bool = False) -> str:
    jql = (
        f'project = {config.jira.default_project} AND assignee = currentUser() '
        'AND status = "배포 대기" ORDER BY updated DESC'
    )
    issues = JiraClient(config.jira).search(jql, max_results=50)
    lines = ["배포 대기 Jira 일감", f"JQL: {jql}", ""]
    if not issues:
        lines.append("배포 대기 상태의 내 일감이 없습니다.")
    for issue in issues:
        fields = issue.get("fields", {}) or {}
        status = (fields.get("status") or {}).get("name", "")
        priority = (fields.get("priority") or {}).get("name", "")
        lines.append(f"- {issue.get('key')} [{status}/{priority}] {fields.get('summary', '')}")
    message = "\n".join(lines)
    if send_slack:
        _send_dev_alert(config, "배포 대기 Jira 일감", message)
    return message


def evening_checklist(config: AppConfig) -> str:
    lines = ["퇴근 전 체크리스트", ""]
    for repo in configured_repositories(config):
        branch = current_branch(repo)
        dirty = status_porcelain(repo)
        ahead, behind = ahead_behind(repo)
        checks = []
        if dirty:
            checks.append(f"미정리 변경 {len(dirty)}개: commit 또는 stash")
        if ahead:
            checks.append(f"미푸시 커밋 {ahead}개: push 또는 PR 상태 확인")
        if behind:
            checks.append(f"원격보다 behind {behind}: 다음 작업 전 최신화 필요")
        if not ISSUE_KEY_PATTERN.search(branch.upper()):
            checks.append("브랜치명에 Jira 키 없음")
        if checks:
            lines.append(f"[{repo.name}] {branch}")
            lines.extend(f"- {item}" for item in checks)
            lines.append("")
    if len(lines) <= 2:
        lines.append("미커밋, 미푸시, 최신화 필요 항목이 없습니다.")
    return "\n".join(lines).strip()


def start_issue_work(
    config: AppConfig,
    issue_key: str,
    *,
    repo_path: str | None = None,
    summary: str = "",
    prefix: str = "feature",
    base_branch: str = "dev",
) -> str:
    issue_key = issue_key.upper()
    summary = summary or _safe_issue_summary(config, issue_key)
    repo = _resolve_issue_repo(config, issue_key, repo_path=repo_path, summary=summary)
    link_issue_repository(config, issue_key, str(repo), summary=summary)
    branch_result = create_branch(config, str(repo), issue_key, summary, prefix=prefix, base_branch=base_branch)
    return "\n".join(
        [
            f"{issue_key} 작업 시작 준비 완료",
            f"- repository: {repo.name} | {repo}",
            f"- summary: {summary or '-'}",
            "",
            branch_result,
        ]
    )


def _resolve_issue_repo(config: AppConfig, issue_key: str, *, repo_path: str | None, summary: str) -> Path:
    repos = configured_repositories(config)
    if repo_path:
        target = Path(repo_path).expanduser().resolve()
        if target not in {repo.resolve() for repo in repos}:
            raise RuntimeError(f"관리 대상 repository가 아닙니다: {target}")
        return target
    links = issue_repository_links()
    if issue_key in links:
        return Path(links[issue_key].repo_path).expanduser().resolve()
    ranked = []
    for repo in repos:
        score = _token_hits(repo.name, summary) * 4 + _count_issue_branches(repo, issue_key) * 30
        if score:
            ranked.append((score, repo))
    if len(ranked) == 1:
        return ranked[0][1]
    if ranked:
        ranked.sort(reverse=True, key=lambda item: item[0])
        top_score = ranked[0][0]
        if len(ranked) == 1 or top_score > ranked[1][0]:
            return ranked[0][1]
    raise RuntimeError("repository를 자동 결정하지 못했습니다. --repo로 작업할 repository를 지정해 주세요.")


def _safe_issue_summary(config: AppConfig, issue_key: str) -> str:
    try:
        issue = JiraClient(config.jira).issue(issue_key)
    except Exception:
        return ""
    return str((issue.get("fields", {}) or {}).get("summary", ""))


def _count_issue_branches(repo: Path, issue_key: str) -> int:
    return len(_issue_branches(repo, issue_key))


def _issue_branches(repo: Path, issue_key: str) -> list[str]:
    try:
        output = git(repo, "branch", "-a", "--format=%(refname:short)")
    except RuntimeError:
        return []
    return [line.strip() for line in output.splitlines() if issue_key.lower() in line.lower()][:12]


def _issue_commits(repo: Path, issue_key: str) -> list[str]:
    try:
        output = git(repo, "log", "--all", "--max-count=30", "--pretty=format:%h | %ad | %s", "--date=short", "--grep", issue_key)
    except RuntimeError:
        return []
    return [line for line in output.splitlines() if line.strip()][:12]


def _issue_pull_requests(repo: Path, issue_key: str) -> list[str]:
    repo_name = owner_repo(repo)
    if not repo_name:
        return []
    rows = _gh_json(
        [
            "gh",
            "pr",
            "list",
            "--repo",
            repo_name,
            "--state",
            "all",
            "--search",
            issue_key,
            "--json",
            "number,title,state,url,headRefName,mergedAt",
            "--limit",
            "20",
        ]
    )
    return [
        f"#{row.get('number')} [{('MERGED' if row.get('mergedAt') else row.get('state'))}] {row.get('title')} | {row.get('headRefName')} | {row.get('url')}"
        for row in rows
    ]


def _open_pull_requests(repo: Path) -> list[dict]:
    repo_name = owner_repo(repo)
    if not repo_name:
        return []
    return _gh_json(
        [
            "gh",
            "pr",
            "list",
            "--repo",
            repo_name,
            "--state",
            "open",
            "--json",
            "number,title,url,headRefName,baseRefName,isDraft,reviewDecision,updatedAt",
            "--limit",
            "30",
        ]
    )


def _count_recent_issue_commits(repo: Path, issue_key: str) -> int:
    return len([line for line in recent_commits(repo, max_count=20) if issue_key.lower() in line.lower()])


def _token_hits(name: str, summary: str) -> int:
    tokens = {token for token in re.split(r"[^a-zA-Z0-9가-힣]+", summary.lower()) if len(token) >= 3}
    if not tokens:
        return 0
    normalized = name.lower().replace("-", " ").replace("_", " ")
    return sum(1 for token in tokens if token in normalized)


def _repo_section(title: str, rows: list[str]) -> str:
    if not rows:
        return ""
    return "\n".join([f"- {title}:"] + [f"  - {row}" for row in rows])


def _gh_json(args: list[str]) -> list[dict]:
    if not any(args):
        return []
    if "--repo" in args:
        repo_index = args.index("--repo") + 1
        if repo_index >= len(args) or not args[repo_index]:
            return []
    try:
        result = subprocess.run(args, check=True, capture_output=True, text=True, encoding="utf-8", errors="replace")
    except (FileNotFoundError, subprocess.CalledProcessError):
        return []
    try:
        payload = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return []
    return payload if isinstance(payload, list) else []


def _send_dev_alert(config: AppConfig, title: str, message: str) -> None:
    SlackClient(config.slack, destination="alerts").send(
        message,
        blocks=[
            header_block(title),
            section_block(message),
            divider_block(),
            context_block("PAS 개발자 비서 알림"),
        ],
    )

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import configured_repositories, git


@dataclass(frozen=True)
class DailyActivity:
    repo: Path
    branch_events: list[str]
    commits: list[str]
    merges: list[str]
    pull_requests: list[str]


def summarize_daily_activity(config: AppConfig) -> str:
    today = datetime.now(ZoneInfo(config.general.timezone)).date().isoformat()
    activities = [collect_daily_activity(repo, today=today, author=config.general.git_author) for repo in configured_repositories(config)]
    return format_daily_activity(activities, today=today)


def collect_daily_activity(repo: Path, *, today: str, author: str) -> DailyActivity:
    return DailyActivity(
        repo=repo,
        branch_events=_branch_events(repo, today=today),
        commits=_commits(repo, today=today, author=author),
        merges=_merges(repo, today=today, author=author),
        pull_requests=_pull_requests(repo, today=today),
    )


def format_daily_activity(activities: list[DailyActivity], *, today: str) -> str:
    if not activities:
        return "관리 중인 repository가 없습니다."

    branch_count = sum(len(item.branch_events) for item in activities)
    commit_count = sum(len(item.commits) for item in activities)
    merge_count = sum(len(item.merges) for item in activities)
    pr_count = sum(len(item.pull_requests) for item in activities)
    lines = [
        f"오늘 개발 흐름 - {today}",
        f"브랜치 이벤트 {branch_count}개 | 커밋 {commit_count}개 | 머지 {merge_count}개 | PR {pr_count}개",
        "",
    ]

    for activity in activities:
        if not activity.branch_events and not activity.commits and not activity.merges and not activity.pull_requests:
            continue
        lines.extend(
            [
                f"[{activity.repo.name}]",
                _section("브랜치 생성/이동", activity.branch_events),
                _section("커밋", activity.commits),
                _section("머지", activity.merges),
                _section("Pull Request", activity.pull_requests),
                "",
            ]
        )

    if len(lines) <= 3:
        lines.append("오늘 확인된 브랜치/커밋/머지/PR 활동이 없습니다.")
    return "\n".join(lines).strip()


def _branch_events(repo: Path, *, today: str) -> list[str]:
    try:
        output = git(repo, "reflog", "--date=iso", f"--since={today} 00:00", "--pretty=%cd | %gs")
    except RuntimeError:
        return []
    rows = []
    for line in output.splitlines():
        if "checkout:" not in line and "branch:" not in line:
            continue
        normalized = line.replace("checkout: moving from ", "").replace("branch: Created from ", "created from ")
        rows.append(normalized)
    return rows[:12]


def _commits(repo: Path, *, today: str, author: str) -> list[str]:
    args = [
        "log",
        f"--since={today} 00:00",
        "--date=iso",
        "--pretty=format:%h | %ad | %s",
    ]
    if author:
        args.insert(2, f"--author={author}")
    try:
        output = git(repo, *args)
    except RuntimeError:
        return []
    return [line for line in output.splitlines() if line.strip()][:20]


def _merges(repo: Path, *, today: str, author: str) -> list[str]:
    args = [
        "log",
        "--merges",
        f"--since={today} 00:00",
        "--date=iso",
        "--pretty=format:%h | %ad | %s",
    ]
    if author:
        args.insert(3, f"--author={author}")
    try:
        output = git(repo, *args)
    except RuntimeError:
        return []
    return [line for line in output.splitlines() if line.strip()][:12]


def _pull_requests(repo: Path, *, today: str) -> list[str]:
    owner_repo = _owner_repo(repo)
    if not owner_repo:
        return []
    args = [
        "gh",
        "pr",
        "list",
        "--repo",
        owner_repo,
        "--state",
        "all",
        "--search",
        f"updated:>={today}",
        "--json",
        "number,title,state,mergedAt,updatedAt,url,headRefName",
        "--limit",
        "20",
    ]
    try:
        result = subprocess.run(args, check=True, capture_output=True, text=True, encoding="utf-8", errors="replace")
    except (FileNotFoundError, subprocess.CalledProcessError):
        return []
    rows = json.loads(result.stdout or "[]")
    items = []
    for row in rows:
        state = "MERGED" if row.get("mergedAt") else str(row.get("state", ""))
        items.append(f"#{row.get('number')} [{state}] {row.get('title')} | {row.get('headRefName')} | {row.get('url')}")
    return items


def _owner_repo(repo: Path) -> str:
    try:
        url = git(repo, "remote", "get-url", "origin")
    except RuntimeError:
        return ""
    patterns = [
        r"github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/.]+)(?:\.git)?$",
        r"github\.com/(?P<owner>[^/]+)/(?P<repo>[^/.]+)(?:\.git)?$",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return f"{match.group('owner')}/{match.group('repo')}"
    return ""


def _section(title: str, rows: list[str]) -> str:
    if not rows:
        return f"- {title}: 없음"
    rendered = [f"- {title}:"]
    rendered.extend(f"  - {row}" for row in rows)
    return "\n".join(rendered)

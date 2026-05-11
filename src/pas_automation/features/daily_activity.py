from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
from pathlib import Path
import subprocess
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import configured_repositories, git, owner_repo


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


def draft_daily_work_report(config: AppConfig, *, manual_notes: str = "") -> str:
    today = datetime.now(ZoneInfo(config.general.timezone)).date().isoformat()
    activities = [collect_daily_activity(repo, today=today, author=config.general.git_author) for repo in configured_repositories(config)]
    return format_daily_work_draft(activities, today=today, manual_notes=manual_notes)


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


def format_daily_work_draft(activities: list[DailyActivity], *, today: str, manual_notes: str = "") -> str:
    active = [
        item
        for item in activities
        if item.commits or item.merges or item.pull_requests
    ]
    commit_count = sum(len(item.commits) for item in active)
    merge_count = sum(len(item.merges) for item in active)
    pr_count = sum(len(item.pull_requests) for item in active)

    lines = [
        f"# 오늘 한 일 초안 - {today}",
        "",
        "## 요약",
    ]
    if active:
        lines.append(f"- 관리 repository {len(active)}곳에서 커밋 {commit_count}개, 머지 커밋 {merge_count}개, PR 활동 {pr_count}개를 확인했습니다.")
    else:
        lines.append("- 오늘 확인된 커밋, 머지, PR 활동이 없습니다.")

    if manual_notes.strip():
        lines.extend(["", "## 수동 메모", manual_notes.strip()])

    lines.extend(["", "## Repository별 작업"])
    if not active:
        lines.append("- 없음")
    for activity in active:
        lines.append(f"### {activity.repo.name}")
        if activity.commits:
            lines.append("- 커밋")
            lines.extend(f"  - {_compact_commit(row)}" for row in activity.commits[:10])
            if len(activity.commits) > 10:
                lines.append(f"  - 외 {len(activity.commits) - 10}개")
        if activity.merges:
            lines.append("- 머지")
            lines.extend(f"  - {_compact_commit(row)}" for row in activity.merges[:8])
            if len(activity.merges) > 8:
                lines.append(f"  - 외 {len(activity.merges) - 8}개")
        merged_prs = [row for row in activity.pull_requests if "[MERGED]" in row]
        if merged_prs:
            lines.append("- 머지된 PR")
            lines.extend(f"  - {row}" for row in merged_prs[:8])
            if len(merged_prs) > 8:
                lines.append(f"  - 외 {len(merged_prs) - 8}개")
        lines.append("")

    lines.extend(
        [
            "## 확인 필요",
            "- 커밋/PR 제목 기준 초안입니다. 실제 배포 여부와 사용자 영향도는 확인 후 보강하세요.",
            "- AI 보고서 작성으로 업그레이드할 때는 위 Git 근거와 수동 메모를 입력 자료로 사용하면 됩니다.",
        ]
    )
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
        "--all",
        "--no-merges",
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
        "--all",
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
    repo_name = owner_repo(repo)
    if not repo_name:
        return []
    args = [
        "gh",
        "pr",
        "list",
        "--repo",
        repo_name,
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
    try:
        rows = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return []
    items = []
    for row in rows:
        state = "MERGED" if row.get("mergedAt") else str(row.get("state", ""))
        items.append(f"#{row.get('number')} [{state}] {row.get('title')} | {row.get('headRefName')} | {row.get('url')}")
    return items


def _compact_commit(row: str) -> str:
    parts = row.split(" | ", 2)
    if len(parts) == 3:
        return f"{parts[0]} {parts[2]}"
    return row

def _section(title: str, rows: list[str]) -> str:
    if not rows:
        return f"- {title}: 없음"
    rendered = [f"- {title}:"]
    rendered.extend(f"  - {row}" for row in rows)
    return "\n".join(rendered)

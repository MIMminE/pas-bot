from __future__ import annotations

from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.github import GitHubBranchStatus, GitHubClient, GitHubPullRequest
from pas_automation.integrations.slack import SlackWebhook, context_block, divider_block, header_block, section_block


def remote_work_report(config: AppConfig, *, days: int = 1, send_slack: bool = False, dry_run: bool = False) -> str:
    if not config.features.git:
        return "Git 기능이 꺼져 있습니다."
    if not config.github.token:
        return "GitHub 토큰 없음: 원격 작업 리포트를 만들 수 없습니다."
    if not config.github.repositories:
        return "GitHub repository 설정 없음: [github.repositories]에 조회할 repository를 추가해 주세요."

    client = GitHubClient(config.github)
    login = client.current_user()
    since = _since_iso(config.general.timezone, days)
    commits = client.commits_since(since, author=login, max_per_repo=50)
    branches = client.active_branches(since, author=login, max_per_repo=50)
    prs = _my_open_prs(client.open_pull_requests(max_per_repo=30), login)

    lines = [
        f"GitHub 원격 작업 리포트 - 최근 {days}일",
        f"사용자: {login or 'unknown'}",
        "",
        f"요약: 내 커밋 {len(commits)}개, 작업중인 브랜치 {len(branches)}개, 내 미처리 PR {len(prs)}개",
        "",
        "[오늘 내가 커밋한 내용]",
        *_format_commits(commits),
        "",
        "[작업중인 원격 브랜치]",
        *_format_branches(branches),
        "",
        "[내 미처리 Pull Request]",
        *_format_prs(prs),
    ]
    message = "\n".join(lines)

    if send_slack and not dry_run:
        SlackWebhook(config.slack, destination="git_report").send(
            message,
            blocks=_remote_report_blocks(days, login, commits, branches, prs),
        )
    return ("[dry-run]\n" if dry_run else "") + message


def remote_branch_status(config: AppConfig, *, send_slack: bool = False, dry_run: bool = False) -> str:
    if not config.features.git:
        return "Git 기능이 꺼져 있습니다."
    if not config.github.token:
        return "GitHub 토큰 없음: 원격 브랜치 상태를 확인할 수 없습니다."
    if not config.github.repositories:
        return "GitHub repository 설정 없음: [github.repositories]에 조회할 repository를 추가해 주세요."

    client = GitHubClient(config.github)
    login = client.current_user()
    statuses = client.branch_statuses(author=login, max_per_repo=80)
    rebase_needed = [item for item in statuses if item.needs_rebase]
    open_prs = [item for item in statuses if item.pull_request is not None]

    lines = [
        "GitHub 원격 브랜치 상태",
        f"사용자: {login or 'unknown'}",
        "",
        f"요약: 내 작업 브랜치 {len(statuses)}개, 리베이스/동기화 필요 {len(rebase_needed)}개, PR 연결 {len(open_prs)}개",
        "",
        "[리베이스/동기화 필요]",
        *_format_branch_statuses(rebase_needed, empty="- 리베이스가 필요한 브랜치가 없습니다."),
        "",
        "[내 작업중인 원격 브랜치]",
        *_format_branch_statuses(statuses, empty="- 내 작업 브랜치를 찾지 못했습니다."),
    ]
    message = "\n".join(lines)

    if send_slack and not dry_run:
        SlackWebhook(config.slack, destination="git_status").send(
            message,
            blocks=_remote_status_blocks(login, statuses, rebase_needed, open_prs),
        )
    return ("[dry-run]\n" if dry_run else "") + message


def _since_iso(timezone: str, days: int) -> str:
    tz = ZoneInfo(timezone)
    today = datetime.now(tz).date()
    start = datetime.combine(today - timedelta(days=max(days - 1, 0)), time.min, tzinfo=tz)
    return start.astimezone(ZoneInfo("UTC")).isoformat().replace("+00:00", "Z")


def _my_open_prs(prs: list[GitHubPullRequest], login: str) -> list[GitHubPullRequest]:
    if not login:
        return prs
    return [item for item in prs if item.author == login]


def _format_commits(commits) -> list[str]:
    if not commits:
        return ["- 원격에서 오늘 내 커밋을 찾지 못했습니다."]
    return [
        f"- {item.repository} `{item.sha}` {item.message} | {item.url}"
        for item in commits[:30]
    ]


def _format_branches(branches) -> list[str]:
    if not branches:
        return ["- 오늘 업데이트된 원격 브랜치를 찾지 못했습니다."]
    return [
        f"- {item.repository} `{item.branch}` {item.message} | {item.url}"
        for item in branches[:30]
    ]


def _format_prs(prs: list[GitHubPullRequest]) -> list[str]:
    if not prs:
        return ["- 내 미처리 PR이 없습니다."]
    return [
        f"- {item.repository} #{item.number} {item.title} ({'draft' if item.draft else item.state}) `{item.head_branch}` | {item.url}"
        for item in prs[:30]
    ]


def _format_branch_statuses(statuses: list[GitHubBranchStatus], *, empty: str) -> list[str]:
    if not statuses:
        return [empty]
    lines: list[str] = []
    for item in statuses[:30]:
        pr_text = f" | PR #{item.pull_request.number}" if item.pull_request else " | PR 없음"
        lines.append(
            f"- {item.repository} `{item.branch}` "
            f"ahead {item.ahead_by} / behind {item.behind_by} / {item.status}"
            f"{pr_text}\n"
            f"  - 최근 커밋: `{item.sha}` {item.message}\n"
            f"  - 제안: {item.recommendation}\n"
            f"  - {item.url}"
        )
    return lines


def _remote_report_blocks(days: int, login: str, commits, branches, prs: list[GitHubPullRequest]) -> list[dict]:
    blocks = [
        header_block("GitHub 원격 작업 리포트"),
        section_block(
            f"*조회 기간* 최근 {days}일\n"
            f"*사용자* `{login or 'unknown'}`\n"
            f"*요약* 내 커밋 `{len(commits)}`개 · 작업중인 브랜치 `{len(branches)}`개 · 내 미처리 PR `{len(prs)}`개"
        ),
        divider_block(),
        section_block("*오늘 내가 커밋한 내용*\n" + "\n".join(_format_commits(commits)[:12])),
        divider_block(),
        section_block("*작업중인 원격 브랜치*\n" + "\n".join(_format_branches(branches)[:12])),
        divider_block(),
        section_block("*내 미처리 Pull Request*\n" + "\n".join(_format_prs(prs)[:12])),
        context_block("PAS GitHub 원격 리포트"),
    ]
    return blocks[:50]


def _remote_status_blocks(
    login: str,
    statuses: list[GitHubBranchStatus],
    rebase_needed: list[GitHubBranchStatus],
    open_prs: list[GitHubBranchStatus],
) -> list[dict]:
    blocks = [
        header_block("GitHub 원격 브랜치 상태"),
        section_block(
            f"*사용자* `{login or 'unknown'}`\n"
            f"*요약* 내 작업 브랜치 `{len(statuses)}`개 · 리베이스/동기화 필요 `{len(rebase_needed)}`개 · PR 연결 `{len(open_prs)}`개"
        ),
        divider_block(),
        section_block("*리베이스/동기화 필요*\n" + "\n".join(_format_branch_statuses(rebase_needed, empty="- 없음")[:8])),
        divider_block(),
        section_block("*내 작업중인 원격 브랜치*\n" + "\n".join(_format_branch_statuses(statuses, empty="- 없음")[:8])),
        context_block("PAS GitHub 원격 브랜치 점검"),
    ]
    return blocks[:50]

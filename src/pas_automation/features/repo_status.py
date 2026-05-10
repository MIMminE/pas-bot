from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import ahead_behind, configured_repositories, snapshot_repo, status_porcelain
from pas_automation.integrations.slack import SlackClient, context_block, divider_block, fields_block, header_block, section_block


@dataclass(frozen=True)
class RepoStatus:
    path: Path
    branch: str
    dirty_count: int
    ahead: int | None
    behind: int | None


def summarize_repositories(config: AppConfig, *, send_slack: bool, dry_run: bool) -> str:
    if not config.features.git_status:
        return "Git 상태 점검 기능이 꺼져 있습니다."
    statuses = collect_repo_status(config)
    message = format_repo_status(statuses)
    if dry_run:
        return "[dry-run]\n" + message
    if send_slack:
        SlackClient(config.slack, destination="git_status").send(message, blocks=repo_status_blocks(statuses))
    return message


def collect_repo_status(config: AppConfig) -> list[RepoStatus]:
    statuses: list[RepoStatus] = []
    for repo in configured_repositories(config):
        snapshot = snapshot_repo(repo)
        dirty = status_porcelain(repo)
        ahead, behind = ahead_behind(repo)
        statuses.append(
            RepoStatus(
                path=repo,
                branch=snapshot.branch,
                dirty_count=len(dirty),
                ahead=ahead,
                behind=behind,
            )
        )
    return sorted(statuses, key=lambda item: str(item.path).lower())


def format_repo_status(statuses: list[RepoStatus]) -> str:
    if not statuses:
        return "등록된 repository root에서 Git repository를 찾지 못했습니다."

    dirty_count = sum(1 for item in statuses if item.dirty_count)
    ahead_count = sum(1 for item in statuses if item.ahead)
    behind_count = sum(1 for item in statuses if item.behind)
    lines = [
        "Git repository 상태",
        f"전체 {len(statuses)}개, 변경 있음 {dirty_count}개, push 필요 {ahead_count}개, rebase/pull 확인 {behind_count}개",
        "",
    ]
    for item in statuses:
        markers = []
        if item.dirty_count:
            markers.append(f"변경 {item.dirty_count}")
        if item.ahead:
            markers.append(f"push +{item.ahead}")
        if item.behind:
            markers.append(f"rebase/pull -{item.behind}")
        if not markers:
            markers.append("clean")
        lines.append(f"- {item.path.name} [{item.branch}] {', '.join(markers)}")
    return "\n".join(lines)


def repo_status_blocks(statuses: list[RepoStatus]) -> list[dict]:
    if not statuses:
        return [header_block("Git repository 상태"), section_block("등록된 repository root에서 Git repository를 찾지 못했습니다.")]

    dirty_count = sum(1 for item in statuses if item.dirty_count)
    ahead_count = sum(1 for item in statuses if item.ahead)
    behind_count = sum(1 for item in statuses if item.behind)
    blocks = [
        header_block("Git repository 상태"),
        fields_block(
            [
                f"*전체*\n{len(statuses)}개",
                f"*변경 있음*\n{dirty_count}개",
                f"*push 필요*\n{ahead_count}개",
                f"*rebase/pull 확인*\n{behind_count}개",
            ]
        ),
        divider_block(),
    ]

    attention = [item for item in statuses if item.dirty_count or item.ahead or item.behind]
    clean = len(statuses) - len(attention)
    for item in attention[:12]:
        markers = []
        if item.dirty_count:
            markers.append(f"`변경 {item.dirty_count}`")
        if item.ahead:
            markers.append(f"`push +{item.ahead}`")
        if item.behind:
            markers.append(f"`rebase/pull -{item.behind}`")
        blocks.append(section_block(f"*{item.path.name}* `{item.branch}`\n{' '.join(markers)}\n`{item.path}`"))
    if clean:
        blocks.append(context_block(f"clean 상태 repository: {clean}개"))
    if len(attention) > 12:
        blocks.append(context_block(f"표시하지 않은 확인 필요 repository: {len(attention) - 12}개"))
    return blocks[:50]

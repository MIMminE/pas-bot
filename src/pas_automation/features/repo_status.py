from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import ahead_behind, configured_repositories, has_issue_key, is_protected_workflow_branch, snapshot_repo, status_porcelain
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
        return "관리 대상으로 등록된 Git repository가 없습니다. 설정에서 gh CLI 후보를 가져와 등록해 주세요."

    dirty_count = sum(1 for item in statuses if item.dirty_count)
    ahead_count = sum(1 for item in statuses if item.ahead)
    behind_count = sum(1 for item in statuses if item.behind)
    branch_policy_count = sum(1 for item in statuses if _branch_policy_attention(item))
    lines = [
        "Git repository 상태",
        f"전체 {len(statuses)}개 | 변경 있음 {dirty_count}개 | push 필요 {ahead_count}개 | rebase/pull 확인 {behind_count}개 | 브랜치 정책 확인 {branch_policy_count}개",
        "",
    ]
    for item in statuses:
        lines.append(f"- {item.path.name} [{item.branch}] {_status_label(item)}")
    return "\n".join(lines)


def repo_status_blocks(statuses: list[RepoStatus]) -> list[dict]:
    if not statuses:
        return [
            header_block("Git repository 상태"),
            section_block("관리 대상으로 등록된 Git repository가 없습니다. 설정에서 gh CLI 후보를 가져와 등록해 주세요."),
        ]

    dirty_count = sum(1 for item in statuses if item.dirty_count)
    ahead_count = sum(1 for item in statuses if item.ahead)
    behind_count = sum(1 for item in statuses if item.behind)
    branch_policy_count = sum(1 for item in statuses if _branch_policy_attention(item))
    attention = [item for item in statuses if item.dirty_count or item.ahead or item.behind or _branch_policy_attention(item)]
    clean_count = len(statuses) - len(attention)

    blocks = [
        header_block("Git repository 상태"),
        fields_block(
            [
                f"*전체 repo*\n{len(statuses)}개",
                f"*변경 있음*\n{dirty_count}개",
                f"*push 필요*\n{ahead_count}개",
                f"*rebase/pull 확인*\n{behind_count}개",
                f"*브랜치 정책 확인*\n{branch_policy_count}개",
            ]
        ),
        context_block(_summary_context(clean_count, len(attention))),
        divider_block(),
    ]

    if not attention:
        blocks.append(section_block("*모든 repository가 정리된 상태입니다.*\n확인 필요한 변경, push, pull/rebase 항목이 없습니다."))
        return blocks[:50]

    blocks.append(section_block("*확인 필요한 repository*"))
    for item in attention[:12]:
        blocks.append(_repo_status_card(item))

    if len(attention) > 12:
        blocks.append(context_block(f"표시하지 않은 확인 필요 repository: {len(attention) - 12}개"))
    if clean_count:
        blocks.append(context_block(f"정상 상태 repository: {clean_count}개"))
    return blocks[:50]


def _repo_status_card(item: RepoStatus) -> dict:
    fields = [
        f"*branch*\n`{item.branch}`",
        f"*상태*\n{_status_label(item)}",
    ]
    if item.dirty_count:
        fields.append(f"*변경 파일*\n{item.dirty_count}개")
    if item.ahead:
        fields.append(f"*push 필요*\nahead {item.ahead}")
    if item.behind:
        fields.append(f"*업데이트 필요*\nbehind {item.behind}")
    if _branch_policy_attention(item):
        fields.append(f"*브랜치 정책*\n{_branch_policy_label(item)}")

    return {
        "type": "section",
        "text": {"type": "mrkdwn", "text": f"*{item.path.name}*\n`{item.path}`"},
        "fields": [{"type": "mrkdwn", "text": field} for field in fields[:10]],
    }


def _status_label(item: RepoStatus) -> str:
    labels = []
    if item.dirty_count:
        labels.append(f"변경 {item.dirty_count}")
    if item.ahead:
        labels.append(f"push +{item.ahead}")
    if item.behind:
        labels.append(f"pull/rebase -{item.behind}")
    if item.ahead is None or item.behind is None:
        labels.append("upstream 없음")
    if _branch_policy_attention(item):
        labels.append(_branch_policy_label(item))
    return ", ".join(labels) if labels else "clean"


def _branch_policy_attention(item: RepoStatus) -> bool:
    return is_protected_workflow_branch(item.branch) or not has_issue_key(item.branch)


def _branch_policy_label(item: RepoStatus) -> str:
    if is_protected_workflow_branch(item.branch):
        return "기준 브랜치 직접 push 제한"
    if not has_issue_key(item.branch):
        return "Jira 키 브랜치 필요"
    return "정상"


def _summary_context(clean_count: int, attention_count: int) -> str:
    if attention_count:
        return f"확인 필요 {attention_count}개 | 정상 {clean_count}개"
    return f"정상 {clean_count}개 | 바로 작업 가능한 상태입니다."

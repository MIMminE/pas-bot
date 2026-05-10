from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import ahead_behind, configured_repositories, current_branch, fetch, pull_ff_only, status_porcelain
from pas_automation.integrations.slack import SlackClient, context_block, divider_block, fields_block, header_block, section_block


@dataclass(frozen=True)
class MorningSyncItem:
    path: Path
    branch: str
    status: str
    detail: str


def morning_sync(config: AppConfig, *, send_slack: bool, dry_run: bool) -> str:
    if not config.features.git_status:
        return "Git 상태 점검 기능이 꺼져 있습니다."

    repos = configured_repositories(config)
    updated: list[MorningSyncItem] = []
    attention: list[MorningSyncItem] = []
    clean: list[MorningSyncItem] = []
    failed: list[MorningSyncItem] = []

    for repo in repos:
        branch = _safe_branch(repo)
        if dry_run:
            _classify_without_changes(repo, branch, updated, attention, clean, failed)
            continue
        try:
            fetch(repo)
            _sync_after_fetch(repo, branch, updated, attention, clean, failed)
        except Exception as exc:
            failed.append(MorningSyncItem(repo, branch, "failed", str(exc)))

    message = _format_text(updated, attention, clean, failed, dry_run=dry_run)
    if send_slack and not dry_run:
        blocks = _format_blocks(updated, attention, clean, failed)
        SlackClient(config.slack, destination="git_status").send(message, blocks=blocks)
        if attention or failed:
            _send_attention_alert(config, message, blocks)
    return "[dry-run]\n" + message if dry_run else message


def _classify_without_changes(
    repo: Path,
    branch: str,
    updated: list[MorningSyncItem],
    attention: list[MorningSyncItem],
    clean: list[MorningSyncItem],
    failed: list[MorningSyncItem],
) -> None:
    try:
        _classify(repo, branch, updated, attention, clean, failed, allow_pull=False)
    except Exception as exc:
        failed.append(MorningSyncItem(repo, branch, "failed", str(exc)))


def _sync_after_fetch(
    repo: Path,
    branch: str,
    updated: list[MorningSyncItem],
    attention: list[MorningSyncItem],
    clean: list[MorningSyncItem],
    failed: list[MorningSyncItem],
) -> None:
    _classify(repo, branch, updated, attention, clean, failed, allow_pull=True)


def _classify(
    repo: Path,
    branch: str,
    updated: list[MorningSyncItem],
    attention: list[MorningSyncItem],
    clean: list[MorningSyncItem],
    failed: list[MorningSyncItem],
    *,
    allow_pull: bool,
) -> None:
    changes = status_porcelain(repo)
    ahead, behind = ahead_behind(repo)
    if changes:
        attention.append(MorningSyncItem(repo, branch, "dirty", f"로컬 변경 파일 {len(changes)}개: commit 또는 stash 필요"))
        return
    if ahead is None or behind is None:
        attention.append(MorningSyncItem(repo, branch, "no-upstream", "upstream 미설정 또는 확인 불가"))
        return
    if ahead and behind:
        attention.append(MorningSyncItem(repo, branch, "diverged", f"브랜치 분기됨: ahead {ahead}, behind {behind}, rebase 판단 필요"))
        return
    if behind:
        if not allow_pull:
            attention.append(MorningSyncItem(repo, branch, "behind", f"자동 최신화 가능 후보: behind {behind}"))
            return
        try:
            pull_ff_only(repo)
            updated.append(MorningSyncItem(repo, branch, "updated", f"fast-forward 업데이트 완료: behind {behind}"))
        except Exception as exc:
            failed.append(MorningSyncItem(repo, branch, "pull-failed", str(exc)))
        return
    if ahead:
        attention.append(MorningSyncItem(repo, branch, "ahead", f"push 필요: ahead {ahead}"))
        return
    clean.append(MorningSyncItem(repo, branch, "clean", "최신 상태"))


def _safe_branch(repo: Path) -> str:
    try:
        return current_branch(repo)
    except Exception:
        return "unknown"


def _format_text(
    updated: list[MorningSyncItem],
    attention: list[MorningSyncItem],
    clean: list[MorningSyncItem],
    failed: list[MorningSyncItem],
    *,
    dry_run: bool,
) -> str:
    lines = [
        "PAS 출근 Git 정비 결과",
        f"자동 최신화 {len(updated)}개, 확인 필요 {len(attention)}개, 실패 {len(failed)}개, 최신 상태 {len(clean)}개",
        "",
    ]
    if dry_run:
        lines.append("dry-run: fetch/pull 없이 현재 로컬 기준으로만 판단했습니다.")
        lines.append("")
    _append_group(lines, "자동 최신화 완료", updated)
    _append_group(lines, "확인 필요", attention)
    _append_group(lines, "실패", failed)
    _append_group(lines, "최신 상태", clean[:12])
    if len(clean) > 12:
        lines.append(f"- 외 최신 상태 repository {len(clean) - 12}개")
    return "\n".join(lines).strip()


def _append_group(lines: list[str], title: str, items: list[MorningSyncItem]) -> None:
    if not items:
        return
    lines.append(title)
    for item in items:
        lines.append(f"- {item.path.name} [{item.branch}] {item.detail}")
    lines.append("")


def _format_blocks(
    updated: list[MorningSyncItem],
    attention: list[MorningSyncItem],
    clean: list[MorningSyncItem],
    failed: list[MorningSyncItem],
) -> list[dict]:
    blocks = [
        header_block("PAS 출근 Git 정비 결과"),
        fields_block(
            [
                f"*자동 최신화*\n{len(updated)}개",
                f"*확인 필요*\n{len(attention)}개",
                f"*실패*\n{len(failed)}개",
                f"*최신 상태*\n{len(clean)}개",
            ]
        ),
        divider_block(),
    ]
    _append_block_group(blocks, "자동 최신화 완료", updated)
    _append_block_group(blocks, "확인 필요", attention)
    _append_block_group(blocks, "실패", failed)
    if clean:
        blocks.append(context_block(f"최신 상태 repository: {len(clean)}개"))
    return blocks[:50]


def _append_block_group(blocks: list[dict], title: str, items: list[MorningSyncItem]) -> None:
    if not items:
        return
    body = "\n".join(f"• *{item.path.name}* `{item.branch}`\n{item.detail}" for item in items[:8])
    if len(items) > 8:
        body += f"\n• 외 {len(items) - 8}개"
    blocks.append(section_block(f"*{title}*\n{body}"))


def _send_attention_alert(config: AppConfig, message: str, blocks: list[dict]) -> None:
    try:
        SlackClient(config.slack, destination="alerts").send(message, blocks=blocks)
    except Exception:
        return

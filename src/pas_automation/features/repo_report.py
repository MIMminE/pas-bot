from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
from pathlib import Path
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import (
    ahead_behind,
    can_snapshot,
    commits_between,
    commits_since,
    configured_repositories,
    snapshot_repo,
    status_porcelain,
)
from pas_automation.integrations.openai_report import build_report
from pas_automation.integrations.slack import SlackClient, context_block, divider_block, fields_block, header_block, section_block


@dataclass(frozen=True)
class RepoReportEntry:
    path: Path
    branch: str
    dirty_count: int
    ahead: int | None
    behind: int | None
    snapshot_commits: str
    today_commits: str

    @property
    def rebase_hint(self) -> str:
        if self.behind and self.ahead:
            return f"upstream과 분기됨. rebase/merge 확인 필요 (ahead {self.ahead}, behind {self.behind})"
        if self.behind:
            return f"rebase 또는 pull 확인 필요 (behind {self.behind})"
        if self.ahead:
            return f"push 필요 (ahead {self.ahead})"
        if self.ahead is None or self.behind is None:
            return "upstream 미설정 또는 확인 불가"
        return "동기화됨"


def snapshot(config: AppConfig, *, name: str) -> Path:
    now = datetime.now(ZoneInfo(config.general.timezone))
    snapshots = []
    skipped = []
    for repo in configured_repositories(config):
        if not can_snapshot(repo):
            skipped.append({"path": str(repo), "reason": "no HEAD"})
            continue
        item = snapshot_repo(repo)
        snapshots.append({"path": item.path, "head": item.head, "branch": item.branch})

    config.general.data_dir.mkdir(parents=True, exist_ok=True)
    output = config.general.data_dir / f"snapshot-{name}.json"
    output.write_text(
        json.dumps(
            {
                "name": name,
                "created_at": now.isoformat(),
                "repositories": snapshots,
                "skipped": skipped,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return output


def report(
    config: AppConfig,
    *,
    snapshot_name: str,
    send_slack: bool,
    dry_run: bool,
) -> str:
    if not config.features.git_report:
        return "Git 일일 보고 기능이 꺼져 있습니다."
    snapshot_path = config.general.data_dir / f"snapshot-{snapshot_name}.json"
    raw = json.loads(snapshot_path.read_text(encoding="utf-8")) if snapshot_path.exists() else {}
    entries = collect_report_entries(config, raw)
    report_material = format_report_material(entries)
    final_report = build_report(config.openai, report_material)

    if dry_run:
        return "[dry-run]\n" + final_report

    if send_slack:
        SlackClient(config.slack, destination="git_report").send(final_report, blocks=_report_blocks(final_report, len(entries)))

    return final_report


def collect_report_entries(config: AppConfig, snapshot_raw: dict | None = None) -> list[RepoReportEntry]:
    snapshot_heads = {
        str(item.get("path")): str(item.get("head"))
        for item in (snapshot_raw or {}).get("repositories", [])
        if item.get("path") and item.get("head")
    }
    entries: list[RepoReportEntry] = []
    since = _today_since(config)
    until = _today_until(config)

    for repo in configured_repositories(config):
        if not can_snapshot(repo):
            continue
        snapshot_item = snapshot_repo(repo)
        dirty = status_porcelain(repo)
        ahead, behind = ahead_behind(repo)
        snapshot_head = snapshot_heads.get(str(repo))
        snapshot_commits = (
            commits_since(repo, snapshot_head, author=config.general.git_author, until=until)
            if snapshot_head
            else ""
        )
        today_commits = commits_between(repo, author=config.general.git_author, since=since, until=until)
        entries.append(
            RepoReportEntry(
                path=repo,
                branch=snapshot_item.branch,
                dirty_count=len(dirty),
                ahead=ahead,
                behind=behind,
                snapshot_commits=snapshot_commits,
                today_commits=today_commits,
            )
        )
    return sorted(entries, key=lambda item: str(item.path).lower())


def format_report_material(entries: list[RepoReportEntry]) -> str:
    if not entries:
        return ""

    sections: list[str] = []
    for entry in entries:
        if not entry.today_commits and not entry.snapshot_commits and not entry.dirty_count and not entry.ahead and not entry.behind:
            continue
        sections.append(
            "\n".join(
                [
                    f"Repository: {entry.path.name}",
                    f"Path: {entry.path}",
                    f"Branch: {entry.branch}",
                    f"Sync: {entry.rebase_hint}",
                    f"Changed files: {entry.dirty_count}",
                    "Today commits:",
                    entry.today_commits or "- 없음",
                    "Snapshot 이후 commits:",
                    entry.snapshot_commits or "- 없음",
                ]
            )
        )
    return "\n\n".join(sections)


def _today_since(config: AppConfig) -> str:
    today = datetime.now(ZoneInfo(config.general.timezone)).date()
    return f"{today.isoformat()} 00:00"


def _today_until(config: AppConfig) -> str:
    today = datetime.now(ZoneInfo(config.general.timezone)).date()
    return f"{today.isoformat()} {config.general.work_end_time}"


def _report_blocks(report_text: str, repo_count: int) -> list[dict]:
    if not report_text.strip():
        return [
            header_block("오늘의 Git 작업 보고서"),
            fields_block(
                [
                    f"*대상 repository*\n{repo_count}개",
                    "*작업 내역*\n확인된 커밋 없음",
                ]
            ),
            section_block("오늘 git 커밋 기준으로 확인된 작업 내역이 없습니다."),
        ]

    sections = _split_report_sections(report_text)
    blocks = [
        header_block("오늘의 Git 작업 보고서"),
        fields_block(
            [
                f"*대상 repository*\n{repo_count}개",
                f"*보고 섹션*\n{len(sections)}개",
            ]
        ),
        context_block("커밋, 브랜치, 변경 상태를 바탕으로 정리한 업무 보고입니다."),
        divider_block(),
    ]

    for index, section in enumerate(sections[:10], start=1):
        title, body = _section_title_body(section, index)
        blocks.append(section_block(f"*{title}*\n>{_quote_text(body)}"))
        if index < min(len(sections), 10):
            blocks.append(divider_block())

    if len(sections) > 10:
        blocks.append(context_block(f"Slack 표시 한도 때문에 나머지 섹션 {len(sections) - 10}개는 생략했습니다."))
    return blocks[:50]


def _split_report_sections(report_text: str) -> list[str]:
    sections = [item.strip() for item in report_text.split("\n\n") if item.strip()]
    if len(sections) <= 1 and len(report_text) > 1200:
        lines = [line.strip() for line in report_text.splitlines() if line.strip()]
        chunks: list[str] = []
        current: list[str] = []
        for line in lines:
            current.append(line)
            if sum(len(item) for item in current) > 800:
                chunks.append("\n".join(current))
                current = []
        if current:
            chunks.append("\n".join(current))
        return chunks
    return sections or [report_text.strip()]


def _section_title_body(section: str, index: int) -> tuple[str, str]:
    lines = [line.strip() for line in section.splitlines() if line.strip()]
    if not lines:
        return f"요약 {index}", ""
    first = lines[0].strip("#-* ")
    if len(first) <= 80:
        return first, "\n".join(lines[1:]) or first
    return f"요약 {index}", "\n".join(lines)


def _quote_text(text: str) -> str:
    clipped = text.strip()
    if len(clipped) > 1700:
        clipped = clipped[:1697].rstrip() + "..."
    return clipped.replace("\n", "\n>")

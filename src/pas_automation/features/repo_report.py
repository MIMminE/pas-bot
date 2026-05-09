from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
from zoneinfo import ZoneInfo

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import can_snapshot, commits_since, discover_repositories, snapshot_repo
from pas_automation.integrations.openai_report import build_report
from pas_automation.integrations.slack import SlackWebhook, context_block, header_block, section_block


def snapshot(config: AppConfig, *, name: str) -> Path:
    now = datetime.now(ZoneInfo(config.general.timezone))
    snapshots = []
    skipped = []
    for root in config.repo_roots:
        for repo in discover_repositories(root.path, recursive=root.recursive):
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
    snapshot_path = config.general.data_dir / f"snapshot-{snapshot_name}.json"
    if not snapshot_path.exists():
        raise RuntimeError(f"Snapshot not found: {snapshot_path}")

    raw = json.loads(snapshot_path.read_text(encoding="utf-8"))
    until = _today_until(config)
    sections = []

    for repo in raw.get("repositories", []):
        repo_path = Path(repo["path"])
        if not repo_path.exists():
            continue
        lines = commits_since(repo_path, repo["head"], author=config.general.git_author, until=until)
        if lines:
            sections.append(f"Repository: {repo_path.name}\n{lines}")

    commits_text = "\n\n".join(sections)
    final_report = build_report(config.openai, commits_text)

    if dry_run:
        return "[dry-run]\n" + final_report

    if send_slack:
        SlackWebhook(config.slack).send(final_report, blocks=_report_blocks(final_report, len(sections)))

    return final_report


def _today_until(config: AppConfig) -> str:
    today = datetime.now(ZoneInfo(config.general.timezone)).date()
    return f"{today.isoformat()} {config.general.work_end_time}"


def _report_blocks(report_text: str, repo_count: int) -> list[dict]:
    return [
        header_block("오늘의 Git 작업 보고서"),
        section_block(report_text or "오늘 git 커밋 기준으로 확인된 작업 내역이 없습니다."),
        context_block(f"커밋이 확인된 repository: {repo_count}개"),
    ]

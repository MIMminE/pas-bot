from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
from zoneinfo import ZoneInfo

from pas_automation.app_state import read_state, write_state
from pas_automation.config import AppConfig
from pas_automation.integrations.slack import SlackClient, section_block


def submit_report(
    config: AppConfig,
    *,
    text: str,
    notes: str = "",
    send_slack: bool = False,
) -> str:
    body = text.strip()
    if not body:
        raise RuntimeError("제출할 보고서 내용이 없습니다.")

    now = datetime.now(ZoneInfo(config.general.timezone))
    submission = {
        "id": f"report-{now.strftime('%Y%m%d%H%M%S')}",
        "date": now.date().isoformat(),
        "submitted_at": now.isoformat(timespec="seconds"),
        "title": _title_from_report(body, now.date().isoformat()),
        "text": body,
        "notes": notes.strip(),
        "slack_sent": False,
    }

    slack_message = ""
    if send_slack:
        SlackClient(config.slack, destination="git_report").send(body, blocks=[section_block(body)])
        submission["slack_sent"] = True
        slack_message = "Slack 전송 완료"
    else:
        slack_message = "Slack 전송 안 함"

    state = read_state()
    reports = list(state.get("submitted_reports") or [])
    reports.append(submission)
    state["submitted_reports"] = reports[-300:]
    write_state(state)

    return "\n".join(
        [
            "보고서를 제출했습니다.",
            f"- id: {submission['id']}",
            f"- date: {submission['date']}",
            f"- app: 기록 저장 완료",
            f"- slack: {slack_message}",
        ]
    )


def submit_report_file(
    config: AppConfig,
    *,
    text_file: str,
    notes_file: str = "",
    send_slack: bool = False,
) -> str:
    text = Path(text_file).expanduser().read_text(encoding="utf-8")
    notes = Path(notes_file).expanduser().read_text(encoding="utf-8") if notes_file else ""
    return submit_report(config, text=text, notes=notes, send_slack=send_slack)


def report_history(*, output_format: str = "json") -> str:
    state = read_state()
    reports = list(state.get("submitted_reports") or [])
    reports = [item for item in reports if isinstance(item, dict)]
    reports.sort(key=lambda item: str(item.get("submitted_at") or ""), reverse=True)
    if output_format == "json":
        return json.dumps(reports, ensure_ascii=False, indent=2)
    if not reports:
        return "제출된 보고서가 없습니다."
    lines = ["제출된 보고서"]
    for item in reports:
        slack = "Slack" if item.get("slack_sent") else "앱"
        lines.append(f"- {item.get('date')} {item.get('title')} | {slack} | {item.get('id')}")
    return "\n".join(lines)


def _title_from_report(text: str, fallback_date: str) -> str:
    for line in text.splitlines():
        value = line.strip().strip("#").strip()
        if value:
            return value[:80]
    return f"{fallback_date} 업무 보고서"

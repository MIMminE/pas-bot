from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
from zoneinfo import ZoneInfo

from pas_automation.app_state import read_state, write_state
from pas_automation.config import AppConfig


def add_work_note(
    config: AppConfig,
    *,
    target_type: str,
    target_id: str,
    target_title: str,
    text: str,
) -> str:
    body = text.strip()
    if not body:
        raise RuntimeError("저장할 메모 내용이 없습니다.")

    now = datetime.now(ZoneInfo(config.general.timezone))
    note = {
        "id": f"note-{now.strftime('%Y%m%d%H%M%S')}",
        "date": now.date().isoformat(),
        "created_at": now.isoformat(timespec="seconds"),
        "target_type": target_type.strip() or "general",
        "target_id": target_id.strip() or "general",
        "target_title": target_title.strip() or "일반 메모",
        "text": body,
    }

    state = read_state()
    notes = list(state.get("work_notes") or [])
    notes.append(note)
    state["work_notes"] = notes[-500:]
    write_state(state)

    return "\n".join(
        [
            "작업 메모를 저장했습니다.",
            f"- id: {note['id']}",
            f"- target: {note['target_type']} · {note['target_id']}",
            f"- date: {note['date']}",
        ]
    )


def add_work_note_file(
    config: AppConfig,
    *,
    target_type: str,
    target_id: str,
    target_title: str,
    text_file: str,
) -> str:
    text = Path(text_file).expanduser().read_text(encoding="utf-8")
    return add_work_note(
        config,
        target_type=target_type,
        target_id=target_id,
        target_title=target_title,
        text=text,
    )


def work_notes(*, output_format: str = "json") -> str:
    state = read_state()
    notes = [item for item in list(state.get("work_notes") or []) if isinstance(item, dict)]
    notes.sort(key=lambda item: str(item.get("created_at") or ""), reverse=True)
    if output_format == "json":
        return json.dumps(notes, ensure_ascii=False, indent=2)
    if not notes:
        return "저장된 작업 메모가 없습니다."
    lines = ["작업 메모"]
    for item in notes:
        lines.append(
            f"- {item.get('date')} [{item.get('target_type')}/{item.get('target_id')}] "
            f"{item.get('target_title')} | {item.get('id')}"
        )
    return "\n".join(lines)

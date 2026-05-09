from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

from pas_automation.config import AppConfig


@dataclass(frozen=True)
class Assignee:
    alias: str
    name: str
    title: str
    account_id: str


def load_assignees(path: Path) -> dict[str, Assignee]:
    if not path.exists():
        return {}
    raw = _read_json(path)
    if not isinstance(raw, dict):
        raise RuntimeError(f"Assignees file must be a JSON object: {path}")

    assignees: dict[str, Assignee] = {}
    for alias, value in raw.items():
        if not isinstance(value, dict):
            continue
        account_id = str(value.get("accountId") or value.get("account_id") or "").strip()
        if not account_id:
            continue
        normalized_alias = str(alias).strip()
        assignees[normalized_alias] = Assignee(
            alias=normalized_alias,
            name=str(value.get("name") or normalized_alias).strip(),
            title=str(value.get("title") or "").strip(),
            account_id=account_id,
        )
    return assignees


def resolve_assignee(config: AppConfig, account_id_or_email_or_alias: str) -> str:
    key = account_id_or_email_or_alias.strip()
    if "@" in key or key.startswith("712020:"):
        return key
    assignee = load_assignees(config.assignees_path).get(key)
    return assignee.account_id if assignee else key


def list_assignees(config: AppConfig) -> str:
    assignees = load_assignees(config.assignees_path)
    if not assignees:
        return f"등록된 Jira 담당자 alias가 없습니다: {config.assignees_path}"
    lines = ["Jira 담당자 alias"]
    for alias in sorted(assignees):
        item = assignees[alias]
        title = f" / {item.title}" if item.title else ""
        lines.append(f"- {item.alias}: {item.name}{title} ({item.account_id})")
    return "\n".join(lines)


def import_assignees(source: str | Path, destination: Path) -> str:
    source_path = Path(source).expanduser().resolve()
    raw = _read_json(source_path)
    if not isinstance(raw, dict):
        raise RuntimeError("담당자 파일은 JSON object 형태여야 합니다.")

    normalized: dict[str, dict[str, str]] = {}
    for alias, value in raw.items():
        if not isinstance(value, dict):
            raise RuntimeError(f"담당자 항목 형식이 올바르지 않습니다: {alias}")
        account_id = str(value.get("accountId") or value.get("account_id") or "").strip()
        if not account_id:
            raise RuntimeError(f"accountId가 없는 담당자 항목입니다: {alias}")
        normalized[str(alias).strip()] = {
            "name": str(value.get("name") or alias).strip(),
            "title": str(value.get("title") or "").strip(),
            "accountId": account_id,
        }

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(normalized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return f"담당자 설정을 가져왔습니다: {destination} ({len(normalized)}명)"


def _read_json(path: Path) -> Any:
    data = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "cp949", "euc-kr"):
        try:
            return json.loads(data.decode(encoding))
        except UnicodeDecodeError:
            continue
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"JSON 형식이 올바르지 않습니다: {path} ({exc})") from exc
    raise RuntimeError(f"지원하지 않는 인코딩의 JSON 파일입니다: {path}")

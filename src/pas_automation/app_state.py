from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil


APP_NAME = "PAS"
STATE_VERSION = 1


def app_data_dir() -> Path:
    override = os.environ.get("PAS_APP_DATA_DIR")
    if override:
        return Path(override).expanduser().resolve()

    return Path.home() / "Library" / "Application Support" / APP_NAME


def init_app_data(*, template_dir: str | Path | None = None) -> Path:
    target = app_data_dir()
    target.mkdir(parents=True, exist_ok=True)
    (target / "logs").mkdir(exist_ok=True)
    (target / "snapshots").mkdir(exist_ok=True)

    templates = Path(template_dir).resolve() if template_dir else Path.cwd()
    _copy_if_missing(templates / "config.example.toml", target / "config.toml")
    _copy_if_missing(templates / "assignees.example.json", target / "assignees.json")
    _copy_if_missing(templates / "report-agent.example.md", target / "report-agent.md")
    _create_json_if_missing(target / "assignees.json", {})
    _create_text_if_missing(target / "report-agent.md", "# PAS Report Agent\n\n- 간결한 한국어 보고서로 작성한다.\n")
    _create_state_if_missing(target / "state.json")
    return target


def default_config_path() -> Path:
    return app_data_dir() / "config.toml"


def default_env_path() -> Path:
    return app_data_dir() / ".env"


def default_assignees_path() -> Path:
    return app_data_dir() / "assignees.json"


def default_state_path() -> Path:
    return app_data_dir() / "state.json"


def default_report_agent_path() -> Path:
    return app_data_dir() / "report-agent.md"


def read_state() -> dict:
    path = default_state_path()
    if not path.exists():
        _create_state_if_missing(path)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"version": STATE_VERSION, "last_runs": {}}


def write_state(state: dict) -> None:
    path = default_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    _write_json(path, state)


def _copy_if_missing(source: Path, destination: Path) -> None:
    if destination.exists() or not source.exists():
        return
    shutil.copyfile(source, destination)


def _create_state_if_missing(destination: Path) -> None:
    if destination.exists():
        return
    payload = {
        "version": STATE_VERSION,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "last_runs": {},
        "issue_repositories": {},
    }
    _write_json(destination, payload)


def _create_json_if_missing(destination: Path, payload: dict) -> None:
    if destination.exists():
        return
    _write_json(destination, payload)


def _create_text_if_missing(destination: Path, payload: str) -> None:
    if destination.exists():
        return
    destination.write_text(payload, encoding="utf-8")


def _write_json(destination: Path, payload: dict) -> None:
    serialized = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    destination.write_text(serialized, encoding="utf-8")

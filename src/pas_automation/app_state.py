from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shutil


APP_NAME = "PAS"
STATE_VERSION = 1


def app_data_dir() -> Path:
    override = os.environ.get("PAS_APP_DATA_DIR")
    if override:
        return Path(override).expanduser().resolve()

    system = platform.system()
    if system == "Darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    if system == "Windows":
        base = os.environ.get("APPDATA")
        if base:
            return Path(base) / APP_NAME
    return Path.home() / ".pas"


def init_app_data(*, template_dir: str | Path | None = None) -> Path:
    target = app_data_dir()
    target.mkdir(parents=True, exist_ok=True)
    (target / "logs").mkdir(exist_ok=True)
    (target / "snapshots").mkdir(exist_ok=True)

    templates = Path(template_dir).resolve() if template_dir else Path.cwd()
    _copy_if_missing(templates / "config.example.toml", target / "config.toml")
    _copy_if_missing(templates / ".env.example", target / ".env")
    _create_state_if_missing(target / "state.json")
    return target


def default_config_path() -> Path:
    return app_data_dir() / "config.toml"


def default_env_path() -> Path:
    return app_data_dir() / ".env"


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
    }
    destination.write_text(json.dumps(payload, indent=2), encoding="utf-8")

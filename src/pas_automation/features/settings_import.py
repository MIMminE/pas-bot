from __future__ import annotations

from pathlib import Path
import shutil
import tomllib

from pas_automation.config import AppConfig
from pas_automation.features.assignees import import_assignees


def import_settings(
    config: AppConfig,
    *,
    config_file: str | None,
    assignees_file: str | None,
) -> str:
    messages: list[str] = []
    if config_file:
        messages.append(import_config_file(config_file, config.root / "config.toml"))
    if assignees_file:
        messages.append(import_assignees(assignees_file, config.assignees_path))
    if not messages:
        return "가져올 설정 파일을 지정해 주세요."
    return "\n".join(messages)


def import_config_file(source: str | Path, destination: Path) -> str:
    source_path = Path(source).expanduser().resolve()
    with source_path.open("rb") as fh:
        tomllib.load(fh)

    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_path, destination)
    return f"config.toml을 가져왔습니다: {destination}"

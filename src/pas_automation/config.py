from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import tomllib


@dataclass(frozen=True)
class GeneralConfig:
    timezone: str
    git_author: str
    work_end_time: str
    data_dir: Path


@dataclass(frozen=True)
class JiraConfig:
    base_url: str
    email: str
    token_env: str
    default_project: str
    todo_jql: str
    yesterday_assigned_jql: str
    stale_jql: str
    high_priority_jql: str


@dataclass(frozen=True)
class SlackConfig:
    webhook_url_env: str


@dataclass(frozen=True)
class OpenAIConfig:
    api_key_env: str
    model: str


@dataclass(frozen=True)
class RepoRoot:
    path: Path
    recursive: bool


@dataclass(frozen=True)
class AppConfig:
    root: Path
    general: GeneralConfig
    jira: JiraConfig
    slack: SlackConfig
    openai: OpenAIConfig
    repo_roots: list[RepoRoot]


def load_config(path: str | Path) -> AppConfig:
    config_path = Path(path).expanduser().resolve()
    with config_path.open("rb") as fh:
        raw = tomllib.load(fh)

    general_raw = raw.get("general", {})
    data_dir = Path(general_raw.get("data_dir", ".pas"))
    if not data_dir.is_absolute():
        data_dir = config_path.parent / data_dir
    if data_dir.name == ".pas":
        data_dir = config_path.parent

    repo_roots_raw = raw.get("repositories", {}).get("roots", [])
    repo_roots = [
        RepoRoot(
            path=Path(item["path"]).expanduser(),
            recursive=bool(item.get("recursive", True)),
        )
        for item in repo_roots_raw
    ]

    return AppConfig(
        root=config_path.parent,
        general=GeneralConfig(
            timezone=general_raw.get("timezone", "Asia/Seoul"),
            git_author=general_raw["git_author"],
            work_end_time=general_raw.get("work_end_time", "18:00"),
            data_dir=data_dir,
        ),
        jira=JiraConfig(
            base_url=_env_or("JIRA_BASE_URL", raw["jira"]["base_url"]).rstrip("/"),
            email=_env_or("JIRA_EMAIL", raw["jira"]["email"]),
            token_env=raw["jira"].get("token_env", "JIRA_API_TOKEN"),
            default_project=_env_or("JIRA_DEFAULT_PROJECT", raw["jira"].get("default_project", "")),
            todo_jql=raw["jira"]["todo_jql"],
            yesterday_assigned_jql=raw["jira"].get(
                "yesterday_assigned_jql",
                "assignee = currentUser() AND assignee CHANGED TO currentUser() DURING (startOfDay(-1), startOfDay())",
            ),
            stale_jql=raw["jira"].get(
                "stale_jql",
                "assignee = currentUser() AND statusCategory != Done AND updated <= -5d",
            ),
            high_priority_jql=raw["jira"].get(
                "high_priority_jql",
                "assignee = currentUser() AND statusCategory != Done AND priority in (Highest, High)",
            ),
        ),
        slack=SlackConfig(
            webhook_url_env=raw["slack"].get("webhook_url_env", "SLACK_WEBHOOK_URL"),
        ),
        openai=OpenAIConfig(
            api_key_env=raw["openai"].get("api_key_env", "OPENAI_API_KEY"),
            model=raw["openai"].get("model", "gpt-4.1-mini"),
        ),
        repo_roots=repo_roots,
    )


def _env_or(name: str, default: str) -> str:
    value = os.environ.get(name)
    return value if value else default

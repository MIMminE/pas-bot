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
    api_token: str
    default_project: str
    todo_jql: str
    yesterday_assigned_jql: str
    stale_jql: str
    high_priority_jql: str


@dataclass(frozen=True)
class SlackConfig:
    webhook_url: str


@dataclass(frozen=True)
class OpenAIConfig:
    api_key: str
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
    assignees_path: Path
    repo_roots: list[RepoRoot]


def load_config(path: str | Path) -> AppConfig:
    config_path = Path(path).expanduser().resolve()
    with config_path.open("rb") as fh:
        raw = tomllib.load(fh)

    general_raw = raw.get("general", {})
    jira_raw = raw.get("jira", {})
    slack_raw = raw.get("slack", {})
    openai_raw = raw.get("openai", {})

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
            base_url=_config_or_env(jira_raw, "base_url", "JIRA_BASE_URL").rstrip("/"),
            email=_config_or_env(jira_raw, "email", "JIRA_EMAIL"),
            api_token=_config_or_env(jira_raw, "api_token", jira_raw.get("token_env", "JIRA_API_TOKEN")),
            default_project=_config_or_env(jira_raw, "default_project", "JIRA_DEFAULT_PROJECT"),
            todo_jql=jira_raw["todo_jql"],
            yesterday_assigned_jql=jira_raw.get(
                "yesterday_assigned_jql",
                "assignee = currentUser() AND assignee CHANGED TO currentUser() DURING (startOfDay(-1), startOfDay())",
            ),
            stale_jql=jira_raw.get(
                "stale_jql",
                "assignee = currentUser() AND statusCategory != Done AND updated <= -5d",
            ),
            high_priority_jql=jira_raw.get(
                "high_priority_jql",
                "assignee = currentUser() AND statusCategory != Done AND priority in (Highest, High)",
            ),
        ),
        slack=SlackConfig(
            webhook_url=_config_or_env(slack_raw, "webhook_url", slack_raw.get("webhook_url_env", "SLACK_WEBHOOK_URL")),
        ),
        openai=OpenAIConfig(
            api_key=_config_or_env(openai_raw, "api_key", openai_raw.get("api_key_env", "OPENAI_API_KEY")),
            model=openai_raw.get("model", "gpt-5-mini"),
        ),
        assignees_path=config_path.parent / "assignees.json",
        repo_roots=repo_roots,
    )


def _config_or_env(section: dict, key: str, env_name: str, default: str = "") -> str:
    value = section.get(key)
    if value:
        return str(value)
    return os.environ.get(env_name, default)

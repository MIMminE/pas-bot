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
class JiraIssueWatchConfig:
    jql: str
    interval_seconds: int


@dataclass(frozen=True)
class SlackConfig:
    mode: str
    bot_token: str
    channels: dict[str, str]

    def channel_for(self, destination: str = "default") -> str:
        return self.channels.get(destination) or self.channels.get("default", "")

    def destination_configured(self, destination: str = "default") -> bool:
        return bool(self.bot_token and self.channel_for(destination))


@dataclass(frozen=True)
class OpenAIConfig:
    api_key: str
    model: str


@dataclass(frozen=True)
class CalendarSource:
    name: str
    url: str
    path: Path | None


@dataclass(frozen=True)
class CalendarConfig:
    enabled: bool
    lookahead_days: int
    sources: list[CalendarSource]


@dataclass(frozen=True)
class FeatureConfig:
    jira: bool
    git: bool
    routines: bool
    ai: bool
    dev_tools: bool
    notifications: bool

    def enabled(self, task_name: str) -> bool:
        return {
            "jira_daily": self.jira,
            "jira_assign": self.jira,
            "git_report": self.git,
            "git_status": self.git,
            "git_morning_sync": self.git,
            "repo_snapshot": self.git,
            "morning_briefing": self.routines,
            "evening_check": self.routines,
            "ai": self.ai,
            "dev_tools": self.dev_tools,
            "notifications": self.notifications,
            "calendar": self.routines,
        }.get(task_name, True)

    @property
    def morning_briefing(self) -> bool:
        return self.routines

    @property
    def evening_check(self) -> bool:
        return self.routines

    @property
    def jira_daily(self) -> bool:
        return self.jira

    @property
    def git_report(self) -> bool:
        return self.git

    @property
    def git_status(self) -> bool:
        return self.git


@dataclass(frozen=True)
class ScheduleConfig:
    enabled: bool
    time: str
    catch_up_if_missed: bool
    weekdays_only: bool
    holiday_dates: set[str]


@dataclass(frozen=True)
class RepoProject:
    path: Path
    base_branch: str = ""


@dataclass(frozen=True)
class AppConfig:
    root: Path
    general: GeneralConfig
    jira: JiraConfig
    jira_issue_watch: JiraIssueWatchConfig
    slack: SlackConfig
    openai: OpenAIConfig
    calendar: CalendarConfig
    features: FeatureConfig
    schedules: dict[str, ScheduleConfig]
    assignees_path: Path
    repo_projects: list[RepoProject]


def load_config(path: str | Path) -> AppConfig:
    config_path = Path(path).expanduser().resolve()
    with config_path.open("rb") as fh:
        raw = tomllib.load(fh)

    general_raw = raw.get("general", {})
    jira_raw = raw.get("jira", {})
    jira_issue_watch_raw = jira_raw.get("issue_watch", {})
    slack_raw = raw.get("slack", {})
    slack_channels_raw = slack_raw.get("channels", {})
    openai_raw = raw.get("openai", {})
    calendar_raw = raw.get("calendar", {})
    features_raw = raw.get("features", {})
    feature_groups_raw = raw.get("feature_groups", {})
    schedules_raw = raw.get("schedules", {})

    data_dir = Path(general_raw.get("data_dir", ".pas"))
    if not data_dir.is_absolute():
        data_dir = config_path.parent / data_dir
    if data_dir.name == ".pas":
        data_dir = config_path.parent

    repo_projects_raw = raw.get("repositories", {}).get("projects", [])
    repo_projects = [
        RepoProject(
            path=Path(item["path"]).expanduser(),
            base_branch=str(item.get("base_branch", "")).strip(),
        )
        for item in repo_projects_raw
        if item.get("path")
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
        jira_issue_watch=JiraIssueWatchConfig(
            jql=str(jira_issue_watch_raw.get("jql", "")).strip(),
            interval_seconds=int(jira_issue_watch_raw.get("interval_seconds", 300) or 300),
        ),
        slack=SlackConfig(
            mode="oauth",
            bot_token=_config_or_env(slack_raw, "bot_token", slack_raw.get("bot_token_env", "SLACK_BOT_TOKEN")),
            channels={
                str(key): str(slack_channels_raw.get(str(key), ""))
                for key in (
                    "default",
                    "test",
                    "morning_briefing",
                    "evening_check",
                    "jira_daily",
                    "git_report",
                    "git_status",
                    "alerts",
                )
            },
        ),
        openai=OpenAIConfig(
            api_key=_config_or_env(openai_raw, "api_key", openai_raw.get("api_key_env", "OPENAI_API_KEY")),
            model=openai_raw.get("model", "gpt-5-mini"),
        ),
        calendar=CalendarConfig(
            enabled=bool(calendar_raw.get("enabled", False)),
            lookahead_days=int(calendar_raw.get("lookahead_days", 1)),
            sources=[
                CalendarSource(
                    name=str(item.get("name", "calendar")),
                    url=str(item.get("url", "")),
                    path=Path(item["path"]).expanduser() if item.get("path") else None,
                )
                for item in calendar_raw.get("sources", [])
            ],
        ),
        features=FeatureConfig(
            jira=_group_enabled(feature_groups_raw, features_raw, "jira", ["jira_daily"]),
            git=_group_enabled(feature_groups_raw, features_raw, "git", ["git_report", "git_status"]),
            routines=_group_enabled(feature_groups_raw, features_raw, "routines", ["morning_briefing", "evening_check"]),
            ai=bool(feature_groups_raw.get("ai", features_raw.get("ai", True))),
            dev_tools=bool(feature_groups_raw.get("dev_tools", features_raw.get("dev_tools", True))),
            notifications=bool(feature_groups_raw.get("notifications", features_raw.get("notifications", True))),
        ),
        schedules={
            task_name: _load_schedule(schedules_raw, task_name, default_time)
            for task_name, default_time in {
                "morning_briefing": "09:00",
                "evening_check": "18:20",
                "jira_daily": "09:00",
                "git_report": "18:30",
                "git_status": "09:10",
                "git_morning_sync": "08:50",
            }.items()
        },
        assignees_path=config_path.parent / "assignees.json",
        repo_projects=repo_projects,
    )


def _config_or_env(section: dict, key: str, env_name: str, default: str = "") -> str:
    value = section.get(key)
    if value:
        return str(value)
    return os.environ.get(env_name, default)


def _load_schedule(raw: dict, task_name: str, default_time: str) -> ScheduleConfig:
    section = raw.get(task_name, {})
    return ScheduleConfig(
        enabled=bool(section.get("enabled", False)),
        time=str(section.get("time", default_time)),
        catch_up_if_missed=bool(section.get("catch_up_if_missed", True)),
        weekdays_only=bool(section.get("weekdays_only", True)),
        holiday_dates={str(item) for item in section.get("holiday_dates", [])},
    )


def _group_enabled(groups: dict, legacy: dict, group_name: str, legacy_keys: list[str]) -> bool:
    if group_name in groups:
        return bool(groups[group_name])
    values = [bool(legacy.get(key, True)) for key in legacy_keys]
    return all(values)

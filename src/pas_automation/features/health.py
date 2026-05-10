from __future__ import annotations

from dataclasses import dataclass

from pas_automation.config import AppConfig
from pas_automation.http import json_request
from pas_automation.integrations.git_repos import configured_repositories
from pas_automation.integrations.jira import JiraClient
from pas_automation.integrations.slack import SlackClient, header_block, list_channels, section_block


@dataclass(frozen=True)
class HealthCheck:
    name: str
    status: str
    detail: str

    @property
    def ok(self) -> bool:
        return self.status == "OK"


def run_health(config: AppConfig, *, check_connections: bool = True, send_alert: bool = False) -> str:
    checks = _required_setting_checks(config)
    if check_connections:
        checks.extend(_connection_checks(config))

    message = _format_health(checks)
    if send_alert and any(not item.ok for item in checks):
        _send_alert(config, checks)
    return message


def _required_setting_checks(config: AppConfig) -> list[HealthCheck]:
    return [
        _required("jira.base_url", config.jira.base_url, "Jira 사이트 URL 필요"),
        _required("jira.email", config.jira.email, "Jira 계정 이메일 필요"),
        _required("jira.api_token", config.jira.api_token, "Jira API 토큰 필요"),
        _required("slack.alerts", config.slack.destination_configured("alerts"), "실패 알림 Slack 목적지 권장"),
        _required("slack.jira_daily", config.slack.destination_configured("jira_daily"), "Jira 브리핑 Slack 목적지 필요"),
        _required("repositories.roots", bool(config.repo_roots), "로컬 Git repository root 필요"),
        _optional("openai.api_key", config.openai.api_key, "AI 초안 생성 시 필요"),
    ]


def _connection_checks(config: AppConfig) -> list[HealthCheck]:
    checks = [
        _check_jira(config),
        _check_slack(config, "alerts"),
        _check_git_roots(config),
        _check_openai(config),
    ]
    return checks


def _required(name: str, value: str, missing: str) -> HealthCheck:
    return HealthCheck(name, "OK", "설정됨") if value else HealthCheck(name, "FAIL", missing)


def _optional(name: str, value: str, missing: str) -> HealthCheck:
    return HealthCheck(name, "OK", "설정됨") if value else HealthCheck(name, "WARN", missing)


def _check_jira(config: AppConfig) -> HealthCheck:
    if not config.jira.base_url or not config.jira.email or not config.jira.api_token:
        return HealthCheck("jira.connection", "FAIL", "Jira URL/email/token 설정 필요")
    try:
        JiraClient(config.jira).search("assignee = currentUser() ORDER BY updated DESC", max_results=1)
        return HealthCheck("jira.connection", "OK", "Jira API 연결 정상")
    except Exception as exc:
        return HealthCheck("jira.connection", "FAIL", str(exc))


def _check_slack(config: AppConfig, destination: str) -> HealthCheck:
    if not config.slack.destination_configured(destination):
        return HealthCheck(f"slack.{destination}", "FAIL", f"{destination} Slack 목적지 설정 필요")
    if config.slack.mode == "oauth":
        try:
            count = len(list_channels(config.slack))
            return HealthCheck(f"slack.{destination}", "OK", f"Slack OAuth 연결 정상: 채널 {count}개 조회")
        except Exception as exc:
            return HealthCheck(f"slack.{destination}", "FAIL", str(exc))
    return HealthCheck(f"slack.{destination}", "OK", "Slack 설정 확인")


def _check_git_roots(config: AppConfig) -> HealthCheck:
    if not config.repo_roots:
        return HealthCheck("git.roots", "FAIL", "로컬 Git repository root 설정 필요")
    missing = []
    for root in config.repo_roots:
        path = root.path.expanduser()
        if not path.exists():
            missing.append(str(path))
            continue
    if missing:
        return HealthCheck("git.roots", "WARN", f"존재하지 않는 root: {', '.join(missing[:3])}")
    total = len(configured_repositories(config))
    if total == 0:
        return HealthCheck("git.roots", "WARN", "설정된 root에서 Git repository를 찾지 못했습니다")
    scope = "관리 대상" if config.repo_projects else "root 하위 전체"
    return HealthCheck("git.roots", "OK", f"{scope} Git repository {total}개 확인")


def _check_openai(config: AppConfig) -> HealthCheck:
    if not config.openai.api_key:
        return HealthCheck("openai.connection", "WARN", "OpenAI API 키 없음")
    try:
        payload = json_request(
            "GET",
            "https://api.openai.com/v1/models",
            headers={"Authorization": f"Bearer {config.openai.api_key}"},
            timeout=20,
        )
        count = len(payload.get("data", [])) if isinstance(payload, dict) else 0
        return HealthCheck("openai.connection", "OK", f"OpenAI API 연결 정상: models {count}개")
    except Exception as exc:
        return HealthCheck("openai.connection", "FAIL", str(exc))


def _format_health(checks: list[HealthCheck]) -> str:
    ok = sum(1 for item in checks if item.status == "OK")
    warn = sum(1 for item in checks if item.status == "WARN")
    fail = sum(1 for item in checks if item.status == "FAIL")
    lines = [
        "PAS API 헬스체크",
        f"OK {ok}개, WARN {warn}개, FAIL {fail}개",
        "",
    ]
    lines.extend(f"[{item.status}] {item.name}: {item.detail}" for item in checks)
    return "\n".join(lines)


def _send_alert(config: AppConfig, checks: list[HealthCheck]) -> None:
    problems = [item for item in checks if not item.ok]
    if not problems:
        return
    text = "\n".join(f"- [{item.status}] {item.name}: {item.detail}" for item in problems[:12])
    SlackClient(config.slack, destination="alerts").send(
        "PAS API 헬스체크 경고",
        blocks=[
            header_block("PAS API 헬스체크 경고"),
            section_block(text),
        ],
    )

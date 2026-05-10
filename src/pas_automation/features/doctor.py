from __future__ import annotations

import shutil

from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import configured_repositories


def run_doctor(config: AppConfig) -> str:
    checks = [
        _check("timezone", bool(config.general.timezone), config.general.timezone),
        _check("git_author", bool(config.general.git_author), config.general.git_author),
        _check("work_end_time", bool(config.general.work_end_time), config.general.work_end_time),
        _check("data_dir", True, str(config.general.data_dir)),
        _check("jira.base_url", bool(config.jira.base_url), config.jira.base_url),
        _check("jira.email", bool(config.jira.email), config.jira.email),
        _secret_check("jira.api_token", bool(config.jira.api_token), "config.toml에 입력 필요"),
        _check("slack.mode", config.slack.mode == "oauth", "oauth"),
        _secret_check("slack.default", config.slack.destination_configured(), "기본 Slack 채널"),
        _secret_check("slack.test", config.slack.destination_configured("test"), "테스트 메시지 채널"),
        _secret_check("slack.jira_daily", config.slack.destination_configured("jira_daily"), "Jira 브리핑 채널"),
        _secret_check("slack.git_report", config.slack.destination_configured("git_report"), "Git 보고서 채널"),
        _secret_check("slack.git_status", config.slack.destination_configured("git_status"), "Git 상태 채널"),
        _secret_check("slack.alerts", config.slack.destination_configured("alerts"), "실패/누락 알림 채널 권장"),
        _check("gh.cli", bool(shutil.which("gh")), "설치됨" if shutil.which("gh") else "GitHub CLI 설치와 gh auth login 필요"),
        _secret_check("openai.api_key", bool(config.openai.api_key), "선택 사항: AI 보고서 사용 시 필요"),
        _check("assignees.json", config.assignees_path.exists(), str(config.assignees_path)),
    ]

    passed = sum(1 for item in checks if item.startswith("[OK]"))
    managed_repos = len(configured_repositories(config))
    lines = [
        "PAS 설정 진단",
        f"필수/주요 항목 {passed}/{len(checks)}개 확인",
        "",
        *checks,
        "",
        "GitHub CLI repository",
        "[OK] gh CLI 후보 조회와 clone으로 등록된 repository만 관리합니다.",
        f"관리 대상 Git repository: {managed_repos}개",
    ]
    return "\n".join(lines)


def _check(name: str, ok: bool, detail: str) -> str:
    status = "OK" if ok else "WARN"
    return f"[{status}] {name}: {detail}"


def _secret_check(name: str, ok: bool, missing_detail: str) -> str:
    return _check(name, ok, "설정됨" if ok else missing_detail)

from __future__ import annotations

from datetime import datetime, time
from zoneinfo import ZoneInfo
import traceback

from pas_automation.app_state import read_state, write_state
from pas_automation.config import AppConfig
from pas_automation.features.jira_daily import format_today_items
from pas_automation.features.repo_report import report
from pas_automation.features.repo_status import summarize_repositories


TASKS = ("jira_daily", "git_report", "git_status")


def tick(config: AppConfig, *, task_name: str | None = None, dry_run: bool = False) -> str:
    selected = [task_name] if task_name else list(TASKS)
    unknown = [task for task in selected if task not in TASKS]
    if unknown:
        raise RuntimeError(f"알 수 없는 자동화 작업입니다: {', '.join(unknown)}")

    now = datetime.now(ZoneInfo(config.general.timezone))
    state = read_state()
    lines = [f"PAS automation tick - {now.isoformat(timespec='seconds')}"]

    for task in selected:
        decision = _should_run(config, state, task, now)
        lines.append(f"{task}: {decision.reason}")
        if not decision.run:
            continue
        if dry_run:
            lines.append(f"{task}: [dry-run] 실행 예정")
            continue
        try:
            _run_task(config, task)
        except Exception as exc:
            _mark_failure(state, task, now, exc)
            write_state(state)
            lines.append(f"{task}: 실패 - {exc}")
            raise
        else:
            _mark_success(state, task, now)
            write_state(state)
            lines.append(f"{task}: 전송 완료")

    return "\n".join(lines)


class _Decision:
    def __init__(self, run: bool, reason: str) -> None:
        self.run = run
        self.reason = reason


def _should_run(config: AppConfig, state: dict, task: str, now: datetime) -> _Decision:
    schedule = config.schedules.get(task)
    if not config.features.enabled(task):
        return _Decision(False, "기능이 꺼져 있습니다")
    if schedule is None or not schedule.enabled:
        return _Decision(False, "스케줄이 꺼져 있습니다")
    if _sent_today(state, task, now):
        return _Decision(False, "오늘 이미 전송했습니다")
    scheduled_time = _parse_time(schedule.time)
    if now.time() >= scheduled_time:
        return _Decision(True, f"설정 시간 {schedule.time} 이후이며 오늘 미전송")
    if schedule.catch_up_if_missed:
        return _Decision(False, f"설정 시간 {schedule.time} 전입니다")
    return _Decision(False, "놓친 실행 보정이 꺼져 있습니다")


def _run_task(config: AppConfig, task: str) -> None:
    if task == "jira_daily":
        format_today_items(config, send_slack=True)
        return
    if task == "git_report":
        report(config, snapshot_name="morning", send_slack=True, dry_run=False)
        return
    if task == "git_status":
        summarize_repositories(config, send_slack=True, dry_run=False)
        return
    raise RuntimeError(f"알 수 없는 자동화 작업입니다: {task}")


def _sent_today(state: dict, task: str, now: datetime) -> bool:
    last_runs = state.get("last_runs", {})
    task_state = last_runs.get(task, {})
    return task_state.get("last_sent_date") == now.date().isoformat()


def _mark_success(state: dict, task: str, now: datetime) -> None:
    state.setdefault("last_runs", {})[task] = {
        "status": "success",
        "last_sent_date": now.date().isoformat(),
        "last_sent_at": now.isoformat(),
    }


def _mark_failure(state: dict, task: str, now: datetime, exc: Exception) -> None:
    state.setdefault("last_runs", {})[task] = {
        "status": "failed",
        "last_failed_at": now.isoformat(),
        "error": str(exc),
        "traceback": traceback.format_exc(limit=5),
    }


def _parse_time(value: str) -> time:
    try:
        hour, minute = value.split(":", 1)
        return time(hour=int(hour), minute=int(minute))
    except ValueError as exc:
        raise RuntimeError(f"스케줄 시간이 올바르지 않습니다: {value}") from exc

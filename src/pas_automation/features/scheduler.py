from __future__ import annotations

import os
from pathlib import Path
import platform
import subprocess
import sys

from pas_automation.app_state import default_config_path
from pas_automation.config import AppConfig, ScheduleConfig


TASK_LABELS = {
    "morning_briefing": "Morning Briefing",
    "evening_check": "Evening Check",
    "jira_daily": "Jira Daily",
    "git_morning_sync": "Git Morning Sync",
    "git_report": "Git Report",
    "git_status": "Git Status",
}

SUPPORTED_SYSTEM = "Darwin"
SYSTEM_LABEL = "macOS"


def install_schedules(config: AppConfig) -> str:
    _require_macos()
    lines = [f"PAS 스케줄 설치 - {SYSTEM_LABEL}"]
    for task, label in TASK_LABELS.items():
        schedule = config.schedules[task]
        _uninstall_launchd(task)
        if not config.features.enabled(task) or not schedule.enabled:
            lines.append(f"{label}: 비활성화 상태라 기존 등록만 제거했습니다")
            continue
        _install_launchd(task, schedule)
        lines.append(f"{label}: {schedule.time} 등록 완료")
    return "\n".join(lines)


def uninstall_schedules() -> str:
    _require_macos()
    lines = [f"PAS 스케줄 제거 - {SYSTEM_LABEL}"]
    for task, label in TASK_LABELS.items():
        _uninstall_launchd(task)
        lines.append(f"{label}: 제거 요청 완료")
    return "\n".join(lines)


def schedule_status(config: AppConfig) -> str:
    _require_macos()
    lines = [f"PAS 스케줄 설정 상태 - {SYSTEM_LABEL}"]
    for task, label in TASK_LABELS.items():
        schedule = config.schedules[task]
        feature = "켜짐" if config.features.enabled(task) else "꺼짐"
        enabled = "켜짐" if schedule.enabled else "꺼짐"
        catch_up = "켜짐" if schedule.catch_up_if_missed else "꺼짐"
        weekdays = "평일만" if schedule.weekdays_only else "매일"
        holidays = f", 제외일 {len(schedule.holiday_dates)}개" if schedule.holiday_dates else ""
        installed = "등록됨" if _task_installed(task) else "미등록"
        lines.append(
            f"{label}: 기능 {feature}, 스케줄 {enabled}, 시간 {schedule.time}, "
            f"{weekdays}{holidays}, 놓친 실행 보정 {catch_up}, OS {installed}"
        )
    return "\n".join(lines)


def _require_macos() -> None:
    system = platform.system()
    if system != SUPPORTED_SYSTEM:
        raise RuntimeError(f"지원하지 않는 OS입니다: {system}. PAS는 현재 macOS 전용입니다.")


def _install_launchd(task: str, schedule: ScheduleConfig) -> None:
    label = _launchd_label(task)
    plist = _launch_agents_dir() / f"{label}.plist"
    hour, minute = _hour_minute(schedule.time)
    program_arguments = "\n".join(f"    <string>{_xml_escape(arg)}</string>" for arg in _pas_tick_command(task))
    plist.write_text(
        f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>{label}</string>
  <key>ProgramArguments</key>
  <array>
{program_arguments}
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>{hour}</integer>
    <key>Minute</key>
    <integer>{minute}</integer>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>{default_config_path().parent / "logs" / (task + ".out.log")}</string>
  <key>StandardErrorPath</key>
  <string>{default_config_path().parent / "logs" / (task + ".err.log")}</string>
</dict>
</plist>
""",
        encoding="utf-8",
    )
    subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(plist)], check=False)


def _uninstall_launchd(task: str) -> None:
    label = _launchd_label(task)
    plist = _launch_agents_dir() / f"{label}.plist"
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}", str(plist)], check=False)
    if plist.exists():
        plist.unlink()


def _task_installed(task: str) -> bool:
    return (_launch_agents_dir() / f"{_launchd_label(task)}.plist").exists()


def _launch_agents_dir() -> Path:
    path = Path.home() / "Library" / "LaunchAgents"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _launchd_label(task: str) -> str:
    return f"com.pas.{task.replace('_', '-')}"


def _hour_minute(value: str) -> tuple[int, int]:
    hour, minute = value.split(":", 1)
    return int(hour), int(minute)


def _pas_tick_command(task: str) -> list[str]:
    if getattr(sys, "frozen", False):
        return [
            sys.executable,
            "--config",
            str(default_config_path()),
            "automation",
            "tick",
            "--task",
            task,
        ]
    return [
        sys.executable,
        "-m",
        "pas_automation.cli",
        "--config",
        str(default_config_path()),
        "automation",
        "tick",
        "--task",
        task,
    ]


def _xml_escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )

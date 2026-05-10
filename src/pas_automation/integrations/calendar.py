from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path
from urllib import request
from zoneinfo import ZoneInfo

from pas_automation.config import CalendarConfig, CalendarSource


@dataclass(frozen=True)
class CalendarEvent:
    calendar: str
    title: str
    starts_at: datetime
    ends_at: datetime | None
    all_day: bool
    location: str


def upcoming_events(config: CalendarConfig, *, timezone: str) -> list[CalendarEvent]:
    if not config.enabled:
        return []
    zone = ZoneInfo(timezone)
    today = datetime.now(zone).date()
    until = today + timedelta(days=max(config.lookahead_days, 1))
    events: list[CalendarEvent] = []
    for source in config.sources:
        text = _read_source(source)
        events.extend(_parse_ics(text, source=source.name, zone=zone))
    return sorted(
        [event for event in events if today <= event.starts_at.date() < until],
        key=lambda item: item.starts_at,
    )


def format_calendar(events: list[CalendarEvent]) -> str:
    if not events:
        return "표시할 캘린더 일정 없음"
    lines: list[str] = []
    for event in events[:10]:
        when = "종일" if event.all_day else event.starts_at.strftime("%H:%M")
        location = f" | {event.location}" if event.location else ""
        lines.append(f"- {when} {event.title} ({event.calendar}){location}")
    if len(events) > 10:
        lines.append(f"- 외 {len(events) - 10}개")
    return "\n".join(lines)


def _read_source(source: CalendarSource) -> str:
    if source.path:
        return Path(source.path).read_text(encoding="utf-8")
    if source.url:
        with request.urlopen(source.url, timeout=20) as response:
            return response.read().decode("utf-8", errors="replace")
    return ""


def _parse_ics(text: str, *, source: str, zone: ZoneInfo) -> list[CalendarEvent]:
    events: list[CalendarEvent] = []
    for block in _event_blocks(_unfold_lines(text)):
        title = block.get("SUMMARY", "")
        starts_at, all_day = _parse_datetime(block.get("DTSTART", ""), zone)
        if starts_at is None:
            continue
        ends_at, _ = _parse_datetime(block.get("DTEND", ""), zone)
        events.append(
            CalendarEvent(
                calendar=source,
                title=title or "(제목 없음)",
                starts_at=starts_at,
                ends_at=ends_at,
                all_day=all_day,
                location=block.get("LOCATION", ""),
            )
        )
    return events


def _unfold_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.splitlines():
        if raw.startswith((" ", "\t")) and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def _event_blocks(lines: list[str]) -> list[dict[str, str]]:
    blocks: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in lines:
        if line == "BEGIN:VEVENT":
            current = {}
            continue
        if line == "END:VEVENT":
            if current is not None:
                blocks.append(current)
            current = None
            continue
        if current is None or ":" not in line:
            continue
        key, value = line.split(":", 1)
        name = key.split(";", 1)[0].upper()
        current[name] = _unescape(value)
    return blocks


def _parse_datetime(value: str, zone: ZoneInfo) -> tuple[datetime | None, bool]:
    if not value:
        return None, False
    if len(value) == 8 and value.isdigit():
        day = date(int(value[:4]), int(value[4:6]), int(value[6:8]))
        return datetime.combine(day, time.min, tzinfo=zone), True
    normalized = value.rstrip("Z")
    try:
        parsed = datetime.strptime(normalized[:15], "%Y%m%dT%H%M%S")
    except ValueError:
        return None, False
    if value.endswith("Z"):
        parsed = parsed.replace(tzinfo=ZoneInfo("UTC")).astimezone(zone)
    else:
        parsed = parsed.replace(tzinfo=zone)
    return parsed, False


def _unescape(value: str) -> str:
    return value.replace("\\n", " ").replace("\\,", ",").replace("\\;", ";").strip()

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from pas_automation.app_state import default_config_path, default_env_path, init_app_data
from pas_automation.config import load_config
from pas_automation.features.ai_assistant import git_summary, incident_draft, jira_issue_summary, monthly_review, pr_description
from pas_automation.features.assignees import list_assignees
from pas_automation.features.automation import tick
from pas_automation.features.daily_activity import summarize_daily_activity
from pas_automation.features.dev_assistant import audit_jira_keys, branch_name, calendar_summary, commit_message, create_branch, dashboard, evening_check, morning_briefing, pr_draft
from pas_automation.features.doctor import run_doctor
from pas_automation.features.health import run_health
from pas_automation.features.issue_repositories import (
    format_issue_repository_links,
    link_issue_repository,
    unlink_issue_repository,
)
from pas_automation.features.jira_daily import assign_issue, format_today_items
from pas_automation.features.repo_report import report, snapshot
from pas_automation.features.repo_morning_sync import morning_sync
from pas_automation.features.repo_status import summarize_repositories
from pas_automation.features.remote_repos import clone_remote_repository, format_remote_repositories, list_remote_repositories
from pas_automation.features.scheduler import install_schedules, schedule_status, uninstall_schedules
from pas_automation.features.settings_import import import_settings
from pas_automation.features.slack_test import send_test_message
from pas_automation.integrations.git_repos import ahead_behind, commits_between, configured_repositories, fetch, pull_ff_only, pull_rebase, push, require_clean_worktree, snapshot_repo, status_porcelain
from pas_automation.integrations.slack import SlackClient, list_channels, section_block
from pas_automation.runtime_env import load_env_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pas", description="PAS 개인 개발자 자동화 비서")
    parser.add_argument("--config", help="사용할 config.toml 경로")
    parser.add_argument("--env", help="호환용 .env 파일 경로")
    parser.add_argument("--template-dir", help="config.example.toml이 있는 템플릿 폴더")

    subparsers = parser.add_subparsers(dest="area", required=True)

    jira = subparsers.add_parser("jira", help="Jira 일감 자동화")
    jira_sub = jira.add_subparsers(dest="command", required=True)
    jira_today = jira_sub.add_parser("today", help="오늘 내 Jira 일감 조회")
    jira_today.add_argument("--max-results", type=int, default=25, help="최대 조회 개수")
    jira_today.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    jira_today.add_argument("--dry-run", action="store_true", help="외부 전송 없이 설정/출력만 확인")

    jira_assign = jira_sub.add_parser("assign", help="Jira 일감 담당자 할당")
    jira_assign.add_argument("issue_key", help="Jira 이슈 키")
    jira_assign.add_argument("account_id_or_email", help="담당자 accountId, 이메일 또는 alias")
    jira_assign.add_argument("--dry-run", action="store_true", help="실제 할당 없이 미리보기")

    jira_link_repo = jira_sub.add_parser("link-repo", help="Jira 일감과 관리 중인 repository 연결")
    jira_link_repo.add_argument("issue_key", help="Jira 이슈 키")
    jira_link_repo.add_argument("--repo", required=True, help="연결할 관리 repository 경로")
    jira_link_repo.add_argument("--summary", default="", help="일감 요약")

    jira_unlink_repo = jira_sub.add_parser("unlink-repo", help="Jira 일감과 repository 연결 해제")
    jira_unlink_repo.add_argument("issue_key", help="Jira 이슈 키")

    jira_repo_links = jira_sub.add_parser("repo-links", help="Jira 일감과 repository 연결 목록")
    jira_repo_links.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    slack = subparsers.add_parser("slack", help="Slack 알림")
    slack_sub = slack.add_subparsers(dest="command", required=True)
    slack_test = slack_sub.add_parser("test", help="Slack 테스트 메시지 전송")
    slack_test.add_argument("--dry-run", action="store_true", help="실제 전송 없이 메시지만 확인")
    slack_test.add_argument(
        "--destination",
        default="test",
        help="전송할 Slack 채널 설정 키: test, jira_daily, git_report, git_status, alerts, default",
    )
    slack_channels = slack_sub.add_parser("channels", help="Slack OAuth 채널 목록 조회")
    slack_channels.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    repo = subparsers.add_parser("repo", help="Git repository 자동화")
    repo_sub = repo.add_subparsers(dest="command", required=True)
    repo_snapshot = repo_sub.add_parser("snapshot", help="현재 repository HEAD 스냅샷 저장")
    repo_snapshot.add_argument("--name", default="morning", help="스냅샷 이름")

    repo_report = repo_sub.add_parser("report", help="스냅샷 이후 Git 작업 보고서 생성")
    repo_report.add_argument("--snapshot", default="morning", help="비교할 스냅샷 이름")
    repo_report.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    repo_report.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")
    repo_report.add_argument("--notes", default="", help="AI 보고서에 함께 반영할 수동 메모")
    repo_report.add_argument("--notes-file", help="AI 보고서에 함께 반영할 수동 메모 파일")
    repo_report.add_argument("--report-agent-file", help="보고서 작성 규칙 Markdown 파일")

    repo_status = repo_sub.add_parser("status", help="관리 repository 변경/push/pull 상태 요약")
    repo_status.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    repo_status.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")

    repo_list = repo_sub.add_parser("list", help="gh CLI로 등록한 관리 Git repository 목록 조회")
    repo_list.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")
    repo_list.add_argument("--all", action="store_true", help="호환용 옵션입니다. 현재는 관리 대상으로 등록한 repository만 조회합니다.")

    repo_remote_list = repo_sub.add_parser("remote-list", help="gh CLI 인증으로 접근 가능한 GitHub repository 후보 조회")
    repo_remote_list.add_argument("--owner", default="", help="조회할 GitHub user/org. 비우면 현재 gh 계정 기준")
    repo_remote_list.add_argument("--limit", type=int, default=200, help="최대 조회 개수")
    repo_remote_list.add_argument("--format", choices=["text", "tsv"], default="text", help="출력 형식")

    repo_clone = repo_sub.add_parser("clone", help="gh CLI로 원격 repository를 clone 위치에 내려받기")
    repo_clone.add_argument("--repo", required=True, help="owner/name, SSH URL 또는 HTTPS URL")
    repo_clone.add_argument("--target-root", required=True, help="clone할 상위 폴더")

    repo_update = repo_sub.add_parser("update", help="관리 중인 repository fetch/pull/rebase/push 실행")
    repo_update.add_argument("--repo", required=True, help="작업할 repository 경로")
    repo_update.add_argument("--mode", choices=["fetch", "pull", "rebase", "push"], default="pull", help="실행할 Git 작업")
    repo_update.add_argument("--dry-run", action="store_true", help="실행할 명령만 확인")

    repo_commits = repo_sub.add_parser("commits", help="repository의 오늘 내 커밋 조회")
    repo_commits.add_argument("--repo", required=True, help="조회할 repository 경로")

    repo_sub.add_parser("activity", help="오늘 브랜치/커밋/머지/PR 활동 요약")

    repo_send_text = repo_sub.add_parser("send-report-text", help="수정한 보고서 텍스트를 Slack으로 전송")
    repo_send_text.add_argument("--text-file", required=True, help="전송할 보고서 텍스트 파일")

    repo_morning_sync = repo_sub.add_parser("morning-sync", help="출근 Git 정비: fetch, 안전한 최신화, 전체 상태 알림")
    repo_morning_sync.add_argument("--send-slack", action="store_true", help="Slack으로 결과 전송")
    repo_morning_sync.add_argument("--dry-run", action="store_true", help="fetch/pull 없이 현재 상태 기준으로 미리보기")

    automation = subparsers.add_parser("automation", help="스케줄러가 호출하는 자동 실행")
    automation_sub = automation.add_subparsers(dest="command", required=True)
    automation_tick = automation_sub.add_parser("tick", help="현재 시간 기준으로 실행할 자동화를 1회 판단")
    automation_tick.add_argument("--task", choices=["morning_briefing", "evening_check", "jira_daily", "git_morning_sync", "git_report", "git_status"], help="특정 자동화 작업만 확인")
    automation_tick.add_argument("--dry-run", action="store_true", help="실행하지 않고 판단 결과만 출력")

    routine = subparsers.add_parser("routine", help="개발자 하루 루틴")
    routine_sub = routine.add_subparsers(dest="command", required=True)
    routine_morning = routine_sub.add_parser("morning", help="출근 브리핑 생성")
    routine_morning.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    routine_morning.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")
    routine_evening = routine_sub.add_parser("evening", help="퇴근 체크 생성")
    routine_evening.add_argument("--send-slack", action="store_true", help="Slack으로 실제 전송")
    routine_evening.add_argument("--dry-run", action="store_true", help="외부 전송 없이 미리보기")

    dev = subparsers.add_parser("dev", help="개발자 보조 도구")
    dev_sub = dev.add_subparsers(dest="command", required=True)
    dev_branch = dev_sub.add_parser("branch-name", help="Jira 키 기반 브랜치명 추천")
    dev_branch.add_argument("issue_key", help="Jira 이슈 키")
    dev_branch.add_argument("summary", help="브랜치명에 넣을 작업 요약")
    dev_branch.add_argument("--prefix", default="feature", help="브랜치 prefix")
    dev_create_branch = dev_sub.add_parser("create-branch", help="Jira 이슈 키 기반 로컬 브랜치 생성")
    dev_create_branch.add_argument("--repo", required=True, help="브랜치를 만들 repository 경로")
    dev_create_branch.add_argument("--issue-key", required=True, help="Jira 이슈 키")
    dev_create_branch.add_argument("--summary", default="", help="브랜치명에 사용할 작업 요약")
    dev_create_branch.add_argument("--prefix", default="feature", help="브랜치 prefix")
    dev_create_branch.add_argument("--base-branch", default="dev", help="작업 브랜치를 시작할 기준 브랜치")
    dev_commit = dev_sub.add_parser("commit-message", help="커밋 메시지 초안 생성")
    dev_commit.add_argument("--repo", help="대상 repository 경로")
    dev_commit.add_argument("--issue-key", help="커밋 메시지에 넣을 Jira 이슈 키")
    dev_pr = dev_sub.add_parser("pr-draft", help="PR 제목/본문 초안 생성")
    dev_pr.add_argument("--repo", help="대상 repository 경로")
    dev_pr.add_argument("--issue-key", help="PR에 연결할 Jira 이슈 키")
    dev_sub.add_parser("audit-jira-keys", help="Jira 키가 없는 브랜치/커밋 점검")
    dev_sub.add_parser("dashboard", help="관리 repository 상태 대시보드")
    dev_sub.add_parser("calendar", help="캘린더 일정 요약")

    ai = subparsers.add_parser("ai", help="AI 보고서/초안 생성")
    ai_sub = ai.add_subparsers(dest="command", required=True)
    ai_git = ai_sub.add_parser("git-summary", help="최근 Git 커밋 기반 작업 요약")
    ai_git.add_argument("--tone", choices=["brief", "detailed", "manager"], default="brief", help="보고 톤")
    ai_git.add_argument("--days", type=int, default=1, help="조회할 최근 일수")
    ai_pr = ai_sub.add_parser("pr-draft", help="AI 기반 PR 제목/본문 초안")
    ai_pr.add_argument("--repo", help="대상 repository 경로")
    ai_pr.add_argument("--issue-key", help="연결할 Jira 이슈 키")
    ai_pr.add_argument("--tone", choices=["brief", "detailed", "manager"], default="brief", help="보고 톤")
    ai_jira = ai_sub.add_parser("jira-summary", help="AI 기반 Jira 이슈 정리")
    ai_jira.add_argument("issue_key", help="Jira 이슈 키")
    ai_jira.add_argument("--tone", choices=["brief", "detailed", "manager"], default="brief", help="보고 톤")
    ai_month = ai_sub.add_parser("monthly-review", help="월간 회고 초안 생성")
    ai_month.add_argument("--month", required=True, help="대상 월: YYYY-MM")
    ai_month.add_argument("--tone", choices=["brief", "detailed", "manager"], default="manager", help="보고 톤")
    ai_incident = ai_sub.add_parser("incident-draft", help="장애/버그 원인 정리 초안")
    ai_incident.add_argument("--issue-key", help="관련 Jira 이슈 키")
    ai_incident.add_argument("--notes", default="", help="추가 메모")
    ai_incident.add_argument("--tone", choices=["brief", "detailed", "manager"], default="detailed", help="보고 톤")

    status = subparsers.add_parser("status", help="설정/연결 상태 진단")
    status_sub = status.add_subparsers(dest="command", required=True)
    status_sub.add_parser("doctor", help="설정값과 관리 repository 진단")
    health = status_sub.add_parser("health", help="API 키/토큰과 실제 연결 상태 확인")
    health.add_argument("--no-network", action="store_true", help="네트워크 호출 없이 필수 설정만 확인")
    health.add_argument("--send-alert", action="store_true", help="실패 항목을 Slack alerts 채널로 전송")

    schedule = subparsers.add_parser("schedule", help="OS 스케줄러 등록/제거")
    schedule_sub = schedule.add_subparsers(dest="command", required=True)
    schedule_sub.add_parser("install", help="현재 설정 기준으로 OS 스케줄러 등록/갱신")
    schedule_sub.add_parser("uninstall", help="PAS OS 스케줄러 항목 제거")
    schedule_sub.add_parser("status", help="스케줄 설정과 OS 등록 상태 표시")

    settings = subparsers.add_parser("settings", help="설정 가져오기와 조회")
    settings_sub = settings.add_subparsers(dest="command", required=True)
    settings_import = settings_sub.add_parser("import", help="config.toml 또는 assignees.json 가져오기")
    settings_import.add_argument("--config-file", help="가져올 config.toml 경로")
    settings_import.add_argument("--assignees-file", help="가져올 assignees.json 경로")
    settings_assignees = settings_sub.add_parser("assignees", help="Jira 담당자 alias 목록")
    settings_assignees.add_argument("action", choices=["list"])

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    init_app_data(template_dir=args.template_dir)
    env_path = args.env or default_env_path()
    config_path = args.config or default_config_path()
    load_env_file(env_path)
    config = load_config(config_path)

    if args.area == "jira" and args.command == "today":
        print(
            format_today_items(
                config,
                max_results=args.max_results,
                dry_run=args.dry_run,
                send_slack=args.send_slack,
            )
        )
        return 0

    if args.area == "jira" and args.command == "assign":
        print(assign_issue(config, args.issue_key, args.account_id_or_email, dry_run=args.dry_run))
        return 0

    if args.area == "jira" and args.command == "link-repo":
        link = link_issue_repository(config, args.issue_key, args.repo, summary=args.summary)
        print(f"{link.issue_key}\t{link.repo_path}\t{link.repo_name}\tlinked")
        return 0

    if args.area == "jira" and args.command == "unlink-repo":
        removed = unlink_issue_repository(args.issue_key)
        print(f"{args.issue_key.upper()}: {'unlinked' if removed else 'not linked'}")
        return 0

    if args.area == "jira" and args.command == "repo-links":
        print(format_issue_repository_links(output_format=args.format))
        return 0

    if args.area == "slack" and args.command == "test":
        print(send_test_message(config, dry_run=args.dry_run, destination=args.destination))
        return 0

    if args.area == "slack" and args.command == "channels":
        channels = list_channels(config.slack)
        if args.format == "tsv":
            print("\n".join(f"{item['id']}\t{item['name']}\t{item['is_private']}" for item in channels))
        else:
            print("Slack 채널 목록")
            print("\n".join(f"- #{item['name']} ({item['id']})" for item in channels))
        return 0

    if args.area == "repo" and args.command == "snapshot":
        output = snapshot(config, name=args.name)
        print(f"Snapshot saved: {output}")
        return 0

    if args.area == "repo" and args.command == "report":
        print(
            report(
                config,
                snapshot_name=args.snapshot,
                send_slack=args.send_slack,
                dry_run=args.dry_run,
                manual_notes=args.notes,
                manual_notes_file=args.notes_file,
                report_agent_file=args.report_agent_file,
            )
        )
        return 0

    if args.area == "repo" and args.command == "status":
        print(summarize_repositories(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "repo" and args.command == "list":
        repos = configured_repositories(config)
        if args.format == "tsv":
            rows = []
            for repo_path in repos:
                snapshot_item = snapshot_repo(repo_path)
                dirty = len(status_porcelain(repo_path))
                ahead, behind = ahead_behind(repo_path)
                rows.append(
                    "\t".join(
                        [
                            str(repo_path),
                            repo_path.name,
                            snapshot_item.branch,
                            "" if ahead is None else str(ahead),
                            "" if behind is None else str(behind),
                            str(dirty),
                        ]
                    )
                )
            print("\n".join(rows))
        else:
            print("Git repository 목록")
            for repo_path in repos:
                snapshot_item = snapshot_repo(repo_path)
                ahead, behind = ahead_behind(repo_path)
                sync = "upstream 없음" if ahead is None or behind is None else f"ahead {ahead}, behind {behind}"
                print(f"- {repo_path.name} [{snapshot_item.branch}] {sync} | {repo_path}")
        return 0

    if args.area == "repo" and args.command == "remote-list":
        repos = list_remote_repositories(owner=args.owner, limit=args.limit)
        print(format_remote_repositories(repos, output_format=args.format))
        return 0

    if args.area == "repo" and args.command == "clone":
        path = clone_remote_repository(repo=args.repo, target_root=args.target_root)
        print(f"{path}\tclone 완료")
        return 0

    if args.area == "repo" and args.command == "update":
        repo_path = _managed_repo_path(config, args.repo)
        command = {
            "fetch": "git fetch --prune",
            "pull": "git pull --ff-only",
            "rebase": "git pull --rebase --autostash",
            "push": "git push",
        }[args.mode]
        if args.dry_run:
            print(f"[dry-run] {repo_path}: {command}")
            return 0

        if args.mode == "fetch":
            output = fetch(repo_path)
        elif args.mode == "pull":
            require_clean_worktree(repo_path, action="업데이트")
            output = pull_ff_only(repo_path)
        elif args.mode == "rebase":
            require_clean_worktree(repo_path, action="Rebase")
            output = pull_rebase(repo_path)
        else:
            output = push(repo_path)
        print(output or f"{repo_path.name}: {command} 완료")
        return 0

    if args.area == "repo" and args.command == "commits":
        repo_path = _managed_repo_path(config, args.repo)
        today = __import__("datetime").date.today().isoformat()
        output = commits_between(
            repo_path,
            author=config.general.git_author,
            since=f"{today} 00:00",
            until=f"{today} {config.general.work_end_time}",
        )
        print(output or "오늘 내 커밋이 없습니다.")
        return 0

    if args.area == "repo" and args.command == "activity":
        print(summarize_daily_activity(config))
        return 0

    if args.area == "repo" and args.command == "send-report-text":
        text = Path(args.text_file).expanduser().read_text(encoding="utf-8")
        SlackClient(config.slack, destination="git_report").send(text, blocks=[section_block(text)])
        print("보고서를 Slack으로 전송했습니다.")
        return 0

    if args.area == "repo" and args.command == "morning-sync":
        print(morning_sync(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "automation" and args.command == "tick":
        print(tick(config, task_name=args.task, dry_run=args.dry_run))
        return 0

    if args.area == "routine" and args.command == "morning":
        print(morning_briefing(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "routine" and args.command == "evening":
        print(evening_check(config, send_slack=args.send_slack, dry_run=args.dry_run))
        return 0

    if args.area == "dev" and args.command == "branch-name":
        print(branch_name(args.issue_key, args.summary, prefix=args.prefix))
        return 0

    if args.area == "dev" and args.command == "create-branch":
        print(create_branch(config, args.repo, args.issue_key, args.summary, prefix=args.prefix, base_branch=args.base_branch))
        return 0

    if args.area == "dev" and args.command == "commit-message":
        print(commit_message(config, args.repo, args.issue_key))
        return 0

    if args.area == "dev" and args.command == "pr-draft":
        print(pr_draft(config, args.repo, args.issue_key))
        return 0

    if args.area == "dev" and args.command == "audit-jira-keys":
        print(audit_jira_keys(config))
        return 0

    if args.area == "dev" and args.command == "dashboard":
        print(dashboard(config))
        return 0

    if args.area == "dev" and args.command == "calendar":
        print(calendar_summary(config))
        return 0

    if args.area == "ai" and args.command == "git-summary":
        print(git_summary(config, tone=args.tone, days=args.days))
        return 0

    if args.area == "ai" and args.command == "pr-draft":
        print(pr_description(config, repo_path=args.repo, issue_key=args.issue_key, tone=args.tone))
        return 0

    if args.area == "ai" and args.command == "jira-summary":
        print(jira_issue_summary(config, issue_key=args.issue_key, tone=args.tone))
        return 0

    if args.area == "ai" and args.command == "monthly-review":
        print(monthly_review(config, month=args.month, tone=args.tone))
        return 0

    if args.area == "ai" and args.command == "incident-draft":
        print(incident_draft(config, issue_key=args.issue_key, notes=args.notes, tone=args.tone))
        return 0

    if args.area == "status" and args.command == "doctor":
        print(run_doctor(config))
        return 0

    if args.area == "status" and args.command == "health":
        print(run_health(config, check_connections=not args.no_network, send_alert=args.send_alert))
        return 0

    if args.area == "schedule" and args.command == "install":
        print(install_schedules(config))
        return 0

    if args.area == "schedule" and args.command == "uninstall":
        print(uninstall_schedules())
        return 0

    if args.area == "schedule" and args.command == "status":
        print(schedule_status(config))
        return 0

    if args.area == "settings" and args.command == "import":
        print(import_settings(config, config_file=args.config_file, assignees_file=args.assignees_file))
        return 0

    if args.area == "settings" and args.command == "assignees" and args.action == "list":
        print(list_assignees(config))
        return 0

    raise RuntimeError("Unknown command")


def _managed_repo_path(config, raw_path: str) -> Path:
    repo_path = Path(raw_path).expanduser().resolve()
    managed = {path.resolve() for path in configured_repositories(config)}
    if repo_path not in managed:
        raise RuntimeError(f"관리 대상 repository가 아닙니다: {repo_path}")
    return repo_path


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"오류: {exc}", file=sys.stderr)
        raise SystemExit(1)

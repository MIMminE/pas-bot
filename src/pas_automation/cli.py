from __future__ import annotations

import argparse

from pas_automation.app_state import default_config_path, default_env_path, init_app_data
from pas_automation.config import load_config
from pas_automation.features.assignees import list_assignees
from pas_automation.features.automation import tick
from pas_automation.features.dev_assistant import audit_jira_keys, branch_name, commit_message, dashboard, evening_check, morning_briefing, pr_draft
from pas_automation.features.doctor import run_doctor
from pas_automation.features.jira_daily import assign_issue, format_today_items
from pas_automation.features.repo_report import report, snapshot
from pas_automation.features.repo_status import summarize_repositories
from pas_automation.features.scheduler import install_schedules, schedule_status, uninstall_schedules
from pas_automation.features.settings_import import import_settings
from pas_automation.features.slack_test import send_test_message
from pas_automation.runtime_env import load_env_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pas", description="Personal automation system")
    parser.add_argument("--config", help="Path to config.toml")
    parser.add_argument("--env", help="Optional legacy .env file")
    parser.add_argument("--template-dir", help="Directory containing config.example.toml")

    subparsers = parser.add_subparsers(dest="area", required=True)

    jira = subparsers.add_parser("jira", help="Jira automations")
    jira_sub = jira.add_subparsers(dest="command", required=True)
    jira_today = jira_sub.add_parser("today", help="Show today's Jira work")
    jira_today.add_argument("--max-results", type=int, default=25)
    jira_today.add_argument("--send-slack", action="store_true")
    jira_today.add_argument("--dry-run", action="store_true")

    jira_assign = jira_sub.add_parser("assign", help="Assign a Jira issue")
    jira_assign.add_argument("issue_key")
    jira_assign.add_argument("account_id_or_email")
    jira_assign.add_argument("--dry-run", action="store_true")

    slack = subparsers.add_parser("slack", help="Slack automations")
    slack_sub = slack.add_subparsers(dest="command", required=True)
    slack_test = slack_sub.add_parser("test", help="Send a Slack webhook test message")
    slack_test.add_argument("--dry-run", action="store_true")
    slack_test.add_argument(
        "--destination",
        default="test",
        help="Slack destination key: test, jira_daily, git_report, git_status, alerts, default",
    )

    repo = subparsers.add_parser("repo", help="Repository automations")
    repo_sub = repo.add_subparsers(dest="command", required=True)
    repo_snapshot = repo_sub.add_parser("snapshot", help="Snapshot repository HEADs")
    repo_snapshot.add_argument("--name", default="morning")

    repo_report = repo_sub.add_parser("report", help="Build daily git report")
    repo_report.add_argument("--snapshot", default="morning")
    repo_report.add_argument("--send-slack", action="store_true")
    repo_report.add_argument("--dry-run", action="store_true")

    repo_status = repo_sub.add_parser("status", help="Summarize local repository health")
    repo_status.add_argument("--send-slack", action="store_true")
    repo_status.add_argument("--dry-run", action="store_true")

    automation = subparsers.add_parser("automation", help="Scheduled automation runner")
    automation_sub = automation.add_subparsers(dest="command", required=True)
    automation_tick = automation_sub.add_parser("tick", help="Run due scheduled automations once")
    automation_tick.add_argument("--task", choices=["morning_briefing", "evening_check", "jira_daily", "git_report", "git_status"])
    automation_tick.add_argument("--dry-run", action="store_true")

    routine = subparsers.add_parser("routine", help="Developer daily routines")
    routine_sub = routine.add_subparsers(dest="command", required=True)
    routine_morning = routine_sub.add_parser("morning", help="Build morning briefing")
    routine_morning.add_argument("--send-slack", action="store_true")
    routine_morning.add_argument("--dry-run", action="store_true")
    routine_evening = routine_sub.add_parser("evening", help="Build evening check")
    routine_evening.add_argument("--send-slack", action="store_true")
    routine_evening.add_argument("--dry-run", action="store_true")

    dev = subparsers.add_parser("dev", help="Developer helper tools")
    dev_sub = dev.add_subparsers(dest="command", required=True)
    dev_branch = dev_sub.add_parser("branch-name", help="Suggest branch name")
    dev_branch.add_argument("issue_key")
    dev_branch.add_argument("summary")
    dev_branch.add_argument("--prefix", default="feature")
    dev_commit = dev_sub.add_parser("commit-message", help="Draft commit message")
    dev_commit.add_argument("--repo")
    dev_commit.add_argument("--issue-key")
    dev_pr = dev_sub.add_parser("pr-draft", help="Draft PR title and body")
    dev_pr.add_argument("--repo")
    dev_pr.add_argument("--issue-key")
    dev_sub.add_parser("audit-jira-keys", help="Find branches/commits without Jira issue keys")
    dev_sub.add_parser("dashboard", help="Show local repo dashboard")

    status = subparsers.add_parser("status", help="Local app status and diagnostics")
    status_sub = status.add_subparsers(dest="command", required=True)
    status_sub.add_parser("doctor", help="Check configuration and local repository roots")

    schedule = subparsers.add_parser("schedule", help="Install or remove OS scheduled tasks")
    schedule_sub = schedule.add_subparsers(dest="command", required=True)
    schedule_sub.add_parser("install", help="Install OS scheduler entries from config")
    schedule_sub.add_parser("uninstall", help="Remove PAS OS scheduler entries")
    schedule_sub.add_parser("status", help="Show schedule configuration")

    settings = subparsers.add_parser("settings", help="Settings import and lookup")
    settings_sub = settings.add_subparsers(dest="command", required=True)
    settings_import = settings_sub.add_parser("import", help="Import config.toml or assignees.json")
    settings_import.add_argument("--config-file", help="Path to config.toml to import")
    settings_import.add_argument("--assignees-file", help="Path to assignees.json to import")
    settings_assignees = settings_sub.add_parser("assignees", help="List Jira assignee aliases")
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

    if args.area == "slack" and args.command == "test":
        print(send_test_message(config, dry_run=args.dry_run, destination=args.destination))
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
            )
        )
        return 0

    if args.area == "repo" and args.command == "status":
        print(summarize_repositories(config, send_slack=args.send_slack, dry_run=args.dry_run))
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

    if args.area == "status" and args.command == "doctor":
        print(run_doctor(config))
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


if __name__ == "__main__":
    raise SystemExit(main())

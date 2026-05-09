from __future__ import annotations

import argparse

from pas_automation.app_state import default_config_path, default_env_path, init_app_data
from pas_automation.config import load_config
from pas_automation.features.jira_daily import assign_issue, format_today_items
from pas_automation.features.repo_report import report, snapshot
from pas_automation.features.slack_test import send_test_message
from pas_automation.runtime_env import load_env_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pas", description="Personal automation system")
    parser.add_argument("--config", help="Path to config.toml")
    parser.add_argument("--env", help="Path to .env file")
    parser.add_argument("--template-dir", help="Directory containing config.example.toml and .env.example")

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

    repo = subparsers.add_parser("repo", help="Repository automations")
    repo_sub = repo.add_subparsers(dest="command", required=True)
    repo_snapshot = repo_sub.add_parser("snapshot", help="Snapshot repository HEADs")
    repo_snapshot.add_argument("--name", default="morning")

    repo_report = repo_sub.add_parser("report", help="Build daily git report")
    repo_report.add_argument("--snapshot", default="morning")
    repo_report.add_argument("--send-slack", action="store_true")
    repo_report.add_argument("--dry-run", action="store_true")

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
        print(send_test_message(config, dry_run=args.dry_run))
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

    raise RuntimeError("Unknown command")


if __name__ == "__main__":
    raise SystemExit(main())

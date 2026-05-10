from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from pas_automation.app_state import read_state, write_state
from pas_automation.config import AppConfig
from pas_automation.integrations.git_repos import configured_repositories


@dataclass(frozen=True)
class IssueRepositoryLink:
    issue_key: str
    repo_path: Path
    repo_name: str
    summary: str
    updated_at: str


def link_issue_repository(config: AppConfig, issue_key: str, repo_path: str, *, summary: str = "") -> IssueRepositoryLink:
    normalized_key = issue_key.strip().upper()
    if not normalized_key:
        raise RuntimeError("Jira issue key is required.")

    repo = Path(repo_path).expanduser().resolve()
    managed = {path.expanduser().resolve() for path in configured_repositories(config)}
    if repo not in managed:
        raise RuntimeError(f"Managed repository is required: {repo}")
    if not (repo / ".git").is_dir():
        raise RuntimeError(f"Git repository not found: {repo}")

    state = read_state()
    links = dict(state.get("issue_repositories") or {})
    updated_at = datetime.now(timezone.utc).isoformat()
    links[normalized_key] = {
        "repo_path": str(repo),
        "repo_name": repo.name,
        "summary": summary.strip(),
        "updated_at": updated_at,
    }
    state["issue_repositories"] = links
    write_state(state)
    return IssueRepositoryLink(normalized_key, repo, repo.name, summary.strip(), updated_at)


def unlink_issue_repository(issue_key: str) -> bool:
    normalized_key = issue_key.strip().upper()
    state = read_state()
    links = dict(state.get("issue_repositories") or {})
    existed = normalized_key in links
    links.pop(normalized_key, None)
    state["issue_repositories"] = links
    write_state(state)
    return existed


def get_issue_repository_link(issue_key: str) -> IssueRepositoryLink | None:
    links = _read_links()
    return links.get(issue_key.strip().upper())


def issue_repository_links() -> dict[str, IssueRepositoryLink]:
    return _read_links()


def format_issue_repository_links(output_format: str = "text") -> str:
    links = issue_repository_links()
    if output_format == "tsv":
        return "\n".join(
            "\t".join([item.issue_key, str(item.repo_path), item.repo_name, item.summary, item.updated_at])
            for item in links.values()
        )
    if not links:
        return "Linked Jira repositories: none"
    rows = ["Linked Jira repositories"]
    for item in links.values():
        summary = f" - {item.summary}" if item.summary else ""
        rows.append(f"- {item.issue_key}: {item.repo_name} | {item.repo_path}{summary}")
    return "\n".join(rows)


def _read_links() -> dict[str, IssueRepositoryLink]:
    state = read_state()
    raw_links = state.get("issue_repositories") or {}
    links: dict[str, IssueRepositoryLink] = {}
    if not isinstance(raw_links, dict):
        return links
    for issue_key, raw in raw_links.items():
        if not isinstance(raw, dict):
            continue
        repo_path = raw.get("repo_path")
        if not repo_path:
            continue
        key = str(issue_key).strip().upper()
        links[key] = IssueRepositoryLink(
            issue_key=key,
            repo_path=Path(str(repo_path)).expanduser(),
            repo_name=str(raw.get("repo_name") or Path(str(repo_path)).name),
            summary=str(raw.get("summary") or ""),
            updated_at=str(raw.get("updated_at") or ""),
        )
    return dict(sorted(links.items(), key=lambda item: item[0]))

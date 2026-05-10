from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess


@dataclass(frozen=True)
class RepoSnapshot:
    path: str
    head: str
    branch: str


def discover_repositories(root: Path, *, recursive: bool) -> list[Path]:
    root = root.resolve()
    if not root.exists():
        return []
    candidates = root.rglob(".git") if recursive else root.glob(".git")
    repos = sorted({item.parent for item in candidates if item.is_dir()})
    return repos


def configured_repositories(config) -> list[Path]:
    selected = {item.path.expanduser().resolve() for item in getattr(config, "repo_projects", [])}
    if selected:
        return sorted((path for path in selected if (path / ".git").is_dir()), key=lambda item: str(item).lower())

    return discovered_repositories(config)


def discovered_repositories(config) -> list[Path]:
    repos: set[Path] = set()
    for root in config.repo_roots:
        repos.update(discover_repositories(root.path.expanduser(), recursive=root.recursive))
    return sorted(repos, key=lambda item: str(item).lower())


def git(repo: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(f"git {' '.join(args)} failed in {repo}: {detail}") from exc
    return result.stdout.strip()


def snapshot_repo(repo: Path) -> RepoSnapshot:
    head = git(repo, "rev-parse", "HEAD")
    branch = git(repo, "branch", "--show-current") or "detached"
    return RepoSnapshot(path=str(repo), head=head, branch=branch)


def can_snapshot(repo: Path) -> bool:
    try:
        git(repo, "rev-parse", "--verify", "HEAD")
    except RuntimeError:
        return False
    return True


def commits_since(repo: Path, since_ref: str, *, author: str, until: str | None) -> str:
    args = [
        "log",
        f"{since_ref}..HEAD",
        "--date=iso",
        f"--author={author}",
        "--pretty=format:%h | %ad | %an | %s",
    ]
    if until:
        args.insert(1, f"--until={until}")
    return git(repo, *args)


def commits_between(repo: Path, *, author: str, since: str, until: str | None) -> str:
    args = [
        "log",
        f"--since={since}",
        "--date=iso",
        f"--author={author}",
        "--pretty=format:%h | %ad | %an | %s",
    ]
    if until:
        args.insert(1, f"--until={until}")
    return git(repo, *args)


def status_porcelain(repo: Path) -> list[str]:
    output = git(repo, "status", "--porcelain=v1")
    return [line for line in output.splitlines() if line.strip()]


def ahead_behind(repo: Path) -> tuple[int | None, int | None]:
    try:
        upstream = git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    except RuntimeError:
        return None, None
    if not upstream:
        return None, None
    counts = git(repo, "rev-list", "--left-right", "--count", f"{upstream}...HEAD").split()
    if len(counts) != 2:
        return None, None
    behind, ahead = int(counts[0]), int(counts[1])
    return ahead, behind


def current_branch(repo: Path) -> str:
    return git(repo, "branch", "--show-current") or "detached"


def recent_commits(repo: Path, *, author: str = "", max_count: int = 10) -> list[str]:
    args = ["log", f"--max-count={max_count}", "--pretty=format:%h | %s"]
    if author:
        args.insert(1, f"--author={author}")
    output = git(repo, *args)
    return [line for line in output.splitlines() if line.strip()]


def staged_files(repo: Path) -> list[str]:
    output = git(repo, "diff", "--cached", "--name-only")
    return [line for line in output.splitlines() if line.strip()]


def changed_files(repo: Path) -> list[str]:
    output = git(repo, "status", "--porcelain=v1")
    return [line[3:] for line in output.splitlines() if line.strip()]

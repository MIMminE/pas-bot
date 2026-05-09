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

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess


@dataclass(frozen=True)
class RepoSnapshot:
    path: str
    head: str
    branch: str

def configured_repositories(config) -> list[Path]:
    selected = {item.path.expanduser().resolve() for item in getattr(config, "repo_projects", [])}
    return sorted((path for path in selected if (path / ".git").is_dir()), key=lambda item: str(item).lower())


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


def require_clean_worktree(repo: Path, *, action: str) -> None:
    changes = status_porcelain(repo)
    if not changes:
        return
    preview = "\n".join(f"- {line}" for line in changes[:12])
    more = "" if len(changes) <= 12 else f"\n- 외 {len(changes) - 12}개"
    raise RuntimeError(
        "\n".join(
            [
                f"{action} 전에 처리되지 않은 변경 파일이 있습니다.",
                "먼저 변경사항을 commit 또는 stash 한 뒤 다시 실행해 주세요.",
                "",
                "변경 파일:",
                preview + more,
            ]
        )
    )


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


def fetch(repo: Path) -> str:
    return git(repo, "fetch", "--prune")


def pull_ff_only(repo: Path) -> str:
    return git(repo, "pull", "--ff-only")


def pull_rebase(repo: Path) -> str:
    return git(repo, "pull", "--rebase", "--autostash")


def push(repo: Path) -> str:
    return git(repo, "push")


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

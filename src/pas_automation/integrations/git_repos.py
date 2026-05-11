from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import subprocess

ISSUE_KEY_PATTERN = re.compile(r"[A-Z][A-Z0-9]+-\d+")
PROTECTED_WORKFLOW_BRANCHES = {"main", "master", "dev", "develop", "development"}


@dataclass(frozen=True)
class RepoSnapshot:
    path: str
    head: str
    branch: str
    base_branch: str
    base_ref: str
    base_behind: int | None
    base_ahead: int | None


@dataclass(frozen=True)
class ConfiguredRepository:
    path: Path
    base_branch: str

def configured_repositories(config) -> list[Path]:
    return [item.path for item in configured_repository_projects(config)]


def configured_repository_projects(config) -> list[ConfiguredRepository]:
    projects: dict[Path, str] = {}
    for item in getattr(config, "repo_projects", []):
        path = item.path.expanduser().resolve()
        if (path / ".git").is_dir():
            projects[path] = getattr(item, "base_branch", "").strip()
    return [
        ConfiguredRepository(path=path, base_branch=base_branch or default_base_branch(path))
        for path, base_branch in sorted(projects.items(), key=lambda item: str(item[0]).lower())
    ]


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


def snapshot_repo(repo: Path, *, base_branch: str = "") -> RepoSnapshot:
    head = git(repo, "rev-parse", "HEAD")
    branch = git(repo, "branch", "--show-current") or "detached"
    effective_base = base_branch.strip() or default_base_branch(repo)
    base_ref = base_reference(repo, effective_base)
    base_behind, base_ahead = base_divergence(repo, base_ref)
    return RepoSnapshot(
        path=str(repo),
        head=head,
        branch=branch,
        base_branch=effective_base,
        base_ref=base_ref,
        base_behind=base_behind,
        base_ahead=base_ahead,
    )


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


def is_protected_workflow_branch(branch: str) -> bool:
    return branch.lower() in PROTECTED_WORKFLOW_BRANCHES


def has_issue_key(branch: str) -> bool:
    return bool(ISSUE_KEY_PATTERN.search(branch.upper()))


def require_jira_work_branch(repo: Path, *, action: str) -> None:
    branch = current_branch(repo)
    if is_protected_workflow_branch(branch):
        raise RuntimeError(
            "\n".join(
                [
                    f"{action} 제한: `{branch}` 브랜치에는 직접 작업/푸시하지 않습니다.",
                    "PAS 기본 정책은 Jira 일감 키가 포함된 작업 브랜치에서 개발한 뒤 PR과 merge로 반영하는 방식입니다.",
                    "Jira 일감에서 `브랜치 시작`을 사용하거나 dev start-issue 명령으로 작업 브랜치를 만든 뒤 다시 실행해 주세요.",
                ]
            )
        )
    if not has_issue_key(branch):
        raise RuntimeError(
            "\n".join(
                [
                    f"{action} 제한: 현재 브랜치 `{branch}`에 Jira 이슈 키가 없습니다.",
                    "브랜치 이름에는 LMS-123 같은 Jira 키가 포함되어야 합니다.",
                    "예: feature/LMS-123-summary",
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
    require_jira_work_branch(repo, action="Push")
    return git(repo, "push")


def current_branch(repo: Path) -> str:
    return git(repo, "branch", "--show-current") or "detached"


def default_base_branch(repo: Path) -> str:
    try:
        origin_head = git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    except RuntimeError:
        origin_head = ""
    if origin_head.startswith("origin/"):
        return origin_head.split("/", 1)[1]
    for branch in ("dev", "develop", "development", "main", "master"):
        if _branch_ref_exists(repo, f"refs/heads/{branch}") or _branch_ref_exists(repo, f"refs/remotes/origin/{branch}"):
            return branch
    return current_branch(repo)


def base_reference(repo: Path, base_branch: str) -> str:
    if base_branch and _branch_ref_exists(repo, f"refs/remotes/origin/{base_branch}"):
        return f"origin/{base_branch}"
    if base_branch and _branch_ref_exists(repo, f"refs/heads/{base_branch}"):
        return base_branch
    return base_branch


def base_divergence(repo: Path, base_ref: str) -> tuple[int | None, int | None]:
    if not base_ref:
        return None, None
    try:
        counts = git(repo, "rev-list", "--left-right", "--count", f"{base_ref}...HEAD").split()
    except RuntimeError:
        return None, None
    if len(counts) != 2:
        return None, None
    behind_base, ahead_base = int(counts[0]), int(counts[1])
    return behind_base, ahead_base


def _branch_ref_exists(repo: Path, ref: str) -> bool:
    try:
        git(repo, "show-ref", "--verify", "--quiet", ref)
    except RuntimeError:
        return False
    return True


def owner_repo(repo: Path) -> str:
    try:
        url = git(repo, "remote", "get-url", "origin")
    except RuntimeError:
        return ""
    patterns = [
        r"github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/.]+)(?:\.git)?$",
        r"github\.com/(?P<owner>[^/]+)/(?P<repo>[^/.]+)(?:\.git)?$",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return f"{match.group('owner')}/{match.group('repo')}"
    return ""


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

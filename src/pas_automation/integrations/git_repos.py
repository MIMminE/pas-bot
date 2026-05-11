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


@dataclass(frozen=True)
class BaseRebaseResult:
    attempted: bool
    succeeded: bool
    message: str = ""


@dataclass(frozen=True)
class BranchOption:
    name: str
    current: bool
    remote: bool
    author: str = ""
    author_email: str = ""


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


def git_result(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


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


def repository_operation_in_progress(repo: Path) -> str:
    git_dir = Path(git(repo, "rev-parse", "--git-dir"))
    if not git_dir.is_absolute():
        git_dir = repo / git_dir
    checks = {
        "rebase 진행 중": ["rebase-merge", "rebase-apply"],
        "merge 진행 중": ["MERGE_HEAD"],
        "cherry-pick 진행 중": ["CHERRY_PICK_HEAD"],
    }
    for label, names in checks.items():
        if any((git_dir / name).exists() for name in names):
            return label
    return ""


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


def auto_rebase_to_base(repo: Path, *, base_branch: str) -> BaseRebaseResult:
    fetch_result = git_result(repo, "fetch", "--prune")
    if fetch_result.returncode != 0:
        return BaseRebaseResult(
            attempted=False,
            succeeded=False,
            message=_git_result_message(fetch_result) or "fetch 실패",
        )

    snapshot = snapshot_repo(repo, base_branch=base_branch)
    if snapshot.branch == "detached":
        return BaseRebaseResult(attempted=False, succeeded=True)
    if snapshot.branch == snapshot.base_branch:
        return _auto_pull_base_branch(repo, snapshot)
    if is_protected_workflow_branch(snapshot.branch):
        return BaseRebaseResult(attempted=False, succeeded=True)
    if not snapshot.base_ref or not snapshot.base_behind:
        return BaseRebaseResult(attempted=False, succeeded=True)

    in_progress = repository_operation_in_progress(repo)
    if in_progress:
        return BaseRebaseResult(attempted=False, succeeded=False, message=in_progress)

    changes = status_porcelain(repo)
    rebase_args = ["rebase", snapshot.base_ref]
    if changes:
        dirty_paths = set(changed_files(repo))
        incoming_paths = set(incoming_base_files(repo, snapshot.base_ref))
        overlapping_paths = sorted(dirty_paths & incoming_paths)
        if overlapping_paths:
            preview = ", ".join(overlapping_paths[:4])
            more = "" if len(overlapping_paths) <= 4 else f" 외 {len(overlapping_paths) - 4}개"
            return BaseRebaseResult(
                attempted=False,
                succeeded=False,
                message=f"변경 파일 {len(changes)}개 중 기준 변경과 겹치는 파일 있음: {preview}{more}",
            )
        rebase_args = ["rebase", "--autostash", snapshot.base_ref]

    original_branch = snapshot.branch
    result = git_result(repo, *rebase_args)
    if result.returncode == 0:
        detail = f"{original_branch} 자동 rebase 완료: {snapshot.base_ref} 기준 behind {snapshot.base_behind}"
        if changes:
            detail += f", 로컬 변경 {len(changes)}개 autostash"
        return BaseRebaseResult(attempted=True, succeeded=True, message=detail)
    message = _rebase_failure_summary(
        result,
        base_ref=snapshot.base_ref,
        branch=original_branch,
        behind=snapshot.base_behind,
        ahead=snapshot.base_ahead,
    )
    abort_result = git_result(repo, "rebase", "--abort")
    if abort_result.returncode != 0:
        abort_message = _git_result_message(abort_result)
        if abort_message:
            message = f"{message}\nrebase abort 실패: {abort_message}"
    return BaseRebaseResult(
        attempted=True,
        succeeded=False,
        message=message,
    )


def _auto_pull_base_branch(repo: Path, snapshot: RepoSnapshot) -> BaseRebaseResult:
    if not snapshot.base_ref or snapshot.base_ref == snapshot.base_branch:
        return BaseRebaseResult(attempted=False, succeeded=True)
    if not snapshot.base_behind:
        return BaseRebaseResult(attempted=False, succeeded=True)
    if snapshot.base_ahead:
        return BaseRebaseResult(
            attempted=False,
            succeeded=False,
            message=f"기준 브랜치 {snapshot.base_branch}가 {snapshot.base_ref}와 갈라짐: ahead {snapshot.base_ahead}, behind {snapshot.base_behind}",
        )
    changes = status_porcelain(repo)
    if changes:
        return BaseRebaseResult(
            attempted=False,
            succeeded=False,
            message=f"기준 브랜치 변경 파일 {len(changes)}개로 자동 pull 보류",
        )
    result = git_result(repo, "merge", "--ff-only", snapshot.base_ref)
    if result.returncode == 0:
        return BaseRebaseResult(
            attempted=True,
            succeeded=True,
            message=f"{snapshot.base_branch} 자동 pull 완료: {snapshot.base_ref} 기준 behind {snapshot.base_behind}",
        )
    return BaseRebaseResult(
        attempted=True,
        succeeded=False,
        message=_git_result_message(result) or f"{snapshot.base_branch} 자동 pull 실패",
    )


def pull_ff_only(repo: Path) -> str:
    return git(repo, "pull", "--ff-only")


def pull_rebase(repo: Path) -> str:
    return git(repo, "pull", "--rebase", "--autostash")


def push(repo: Path) -> str:
    require_jira_work_branch(repo, action="Push")
    return git(repo, "push")


def branch_options(repo: Path, *, base_branch: str = "", author_identities: set[str] | None = None) -> list[BranchOption]:
    current = current_branch(repo)
    identities = {_normalize_identity(item) for item in (author_identities or set()) if item}
    base = base_branch.strip() or default_base_branch(repo)
    local_output = git(repo, "branch", "--format=%(refname:short)")
    options: dict[str, BranchOption] = {}
    for line in local_output.splitlines():
        name = line.strip()
        if name:
            options[name] = BranchOption(name=name, current=name == current, remote=False)

    try:
        remote_output = git(
            repo,
            "for-each-ref",
            "refs/remotes",
            "--format=%(refname:short)%09%(authorname)%09%(authoremail)",
        )
    except RuntimeError:
        remote_output = ""
    for line in remote_output.splitlines():
        parts = line.split("\t")
        remote_name = parts[0].strip() if parts else ""
        author = parts[1].strip() if len(parts) > 1 else ""
        author_email = parts[2].strip().strip("<>") if len(parts) > 2 else ""
        if not remote_name or remote_name.endswith("/HEAD"):
            continue
        short_name = remote_name.split("/", 1)[1] if remote_name.startswith("origin/") else remote_name
        if "�" in short_name:
            continue
        include_remote = short_name == base or _matches_identity(author, author_email, identities)
        if not include_remote:
            continue
        if short_name not in options:
            options[short_name] = BranchOption(name=short_name, current=False, remote=True, author=author, author_email=author_email)

    return sorted(options.values(), key=lambda item: (item.remote, item.name.lower()))


def checkout_branch(repo: Path, branch: str) -> str:
    target = branch.strip()
    if not target:
        raise RuntimeError("체크아웃할 브랜치를 지정해 주세요.")
    require_clean_worktree(repo, action="브랜치 변경")
    if _branch_ref_exists(repo, f"refs/heads/{target}"):
        return git(repo, "checkout", target)
    remote = f"origin/{target}"
    if _branch_ref_exists(repo, f"refs/remotes/{remote}"):
        return git(repo, "checkout", "-b", target, "--track", remote)
    raise RuntimeError(f"브랜치를 찾지 못했습니다: {target}")


def current_branch(repo: Path) -> str:
    return git(repo, "branch", "--show-current") or "detached"


def default_base_branch(repo: Path) -> str:
    for branch in ("dev", "develop", "development", "stage", "main", "master"):
        if _branch_ref_exists(repo, f"refs/heads/{branch}") or _branch_ref_exists(repo, f"refs/remotes/origin/{branch}"):
            return branch
    try:
        origin_head = git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    except RuntimeError:
        origin_head = ""
    if origin_head.startswith("origin/"):
        return origin_head.split("/", 1)[1]
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


def incoming_base_files(repo: Path, base_ref: str) -> list[str]:
    if not base_ref:
        return []
    try:
        merge_base = git(repo, "merge-base", "HEAD", base_ref)
        output = git(repo, "diff", "--name-only", f"{merge_base}..{base_ref}")
    except RuntimeError:
        return []
    return [line for line in output.splitlines() if line.strip()]


def ref_last_commit_summary(repo: Path, ref: str) -> str:
    if not ref:
        return ""
    try:
        output = git(repo, "log", "-1", "--date=format:%m/%d %H:%M", "--pretty=format:%h|%cr|%cd", ref)
    except RuntimeError:
        return ""
    parts = output.split("|", 2)
    if len(parts) != 3:
        return output
    short_hash, relative_time, committed_at = parts
    return f"{short_hash} · {relative_time} · {committed_at}"


def _branch_ref_exists(repo: Path, ref: str) -> bool:
    try:
        git(repo, "show-ref", "--verify", "--quiet", ref)
    except RuntimeError:
        return False
    return True


def _git_result_message(result: subprocess.CompletedProcess[str]) -> str:
    return (result.stderr or result.stdout or "").strip()


def _matches_identity(author: str, author_email: str, identities: set[str]) -> bool:
    if not identities:
        return True
    values = {_normalize_identity(author), _normalize_identity(author_email)}
    if values & identities:
        return True
    email = _normalize_identity(author_email)
    return any(identity and identity in email for identity in identities)


def _normalize_identity(value: str) -> str:
    return value.strip().strip("<>").lower()


def _rebase_failure_summary(
    result: subprocess.CompletedProcess[str],
    *,
    base_ref: str,
    branch: str,
    behind: int | None,
    ahead: int | None,
) -> str:
    detail = _git_result_message(result)
    conflict = _first_matching_line(detail, ("could not apply", "CONFLICT", "error:"))
    counts = []
    if behind is not None:
        counts.append(f"behind {behind}")
    if ahead is not None:
        counts.append(f"ahead {ahead}")
    count_text = f" ({', '.join(counts)})" if counts else ""
    if conflict:
        return f"{branch} -> {base_ref} 자동 rebase 충돌{count_text}: {conflict}"
    return f"{branch} -> {base_ref} 자동 rebase 실패{count_text}"


def _first_matching_line(text: str, patterns: tuple[str, ...]) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if any(pattern in stripped for pattern in patterns):
            return stripped
    return ""


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
    paths: list[str] = []
    for line in output.splitlines():
        if not line.strip():
            continue
        raw_path = line[3:]
        if " -> " in raw_path:
            paths.extend(path for path in raw_path.split(" -> ", 1) if path)
        else:
            paths.append(raw_path)
    return paths

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import subprocess


@dataclass(frozen=True)
class RemoteRepository:
    name_with_owner: str
    ssh_url: str
    url: str
    visibility: str
    default_branch: str


def list_remote_repositories(*, owner: str = "", limit: int = 200) -> list[RemoteRepository]:
    args = [
        "gh",
        "repo",
        "list",
    ]
    if owner.strip():
        args.append(owner.strip())
    args.extend(
        [
            "--limit",
            str(limit),
            "--json",
            "nameWithOwner,sshUrl,url,visibility,defaultBranchRef",
        ]
    )
    output = _run(args)
    rows = json.loads(output or "[]")
    repos: list[RemoteRepository] = []
    for row in rows:
        default_branch = row.get("defaultBranchRef") or {}
        repos.append(
            RemoteRepository(
                name_with_owner=str(row.get("nameWithOwner", "")),
                ssh_url=str(row.get("sshUrl", "")),
                url=str(row.get("url", "")),
                visibility=str(row.get("visibility", "")),
                default_branch=str(default_branch.get("name", "")),
            )
        )
    return sorted(repos, key=lambda item: item.name_with_owner.lower())


def format_remote_repositories(repos: list[RemoteRepository], *, output_format: str) -> str:
    if output_format == "tsv":
        return "\n".join(
            "\t".join(
                [
                    repo.name_with_owner,
                    repo.ssh_url,
                    repo.url,
                    repo.visibility,
                    repo.default_branch,
                ]
            )
            for repo in repos
        )

    if not repos:
        return "조회 가능한 GitHub repository가 없습니다."
    lines = ["GitHub remote repository 후보"]
    for repo in repos:
        lines.append(f"- {repo.name_with_owner} [{repo.visibility}] {repo.default_branch} | {repo.ssh_url or repo.url}")
    return "\n".join(lines)


def clone_remote_repository(*, repo: str, target_root: str) -> Path:
    if not repo.strip():
        raise RuntimeError("clone할 repository를 입력해 주세요.")
    root = Path(target_root).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    repo_name = repo.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")
    target = root / repo_name
    if (target / ".git").is_dir():
        _run(["git", "-C", str(target), "fetch", "--prune"])
        return target
    if target.exists():
        raise RuntimeError(f"이미 같은 이름의 경로가 있지만 Git repository가 아닙니다: {target}")
    _run(["gh", "repo", "clone", repo, str(target)])
    return target


def _run(args: list[str]) -> str:
    try:
        result = subprocess.run(
            args,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        tool = args[0]
        if tool == "gh":
            message = "gh CLI를 찾지 못했습니다. 먼저 GitHub CLI를 설치하고 gh auth login을 실행해 주세요."
        else:
            message = f"{tool} 실행 파일을 찾지 못했습니다."
        raise RuntimeError(message) from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(f"{' '.join(args)} 실패: {detail}") from exc
    return result.stdout.strip()

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote, urlencode

from pas_automation.config import GitHubConfig, GitHubRepository
from pas_automation.http import json_request


@dataclass(frozen=True)
class GitHubBranchMatch:
    repository: str
    branch: str
    url: str


@dataclass(frozen=True)
class GitHubPullRequest:
    repository: str
    number: int
    title: str
    url: str
    state: str
    draft: bool
    author: str = ""
    head_branch: str = ""
    updated_at: str = ""


@dataclass(frozen=True)
class GitHubCommit:
    repository: str
    sha: str
    message: str
    author: str
    date: str
    url: str


@dataclass(frozen=True)
class GitHubBranchActivity:
    repository: str
    branch: str
    sha: str
    message: str
    author: str
    date: str
    url: str


@dataclass(frozen=True)
class GitHubBranchStatus:
    repository: str
    default_branch: str
    branch: str
    sha: str
    message: str
    author: str
    author_login: str
    date: str
    url: str
    ahead_by: int
    behind_by: int
    status: str
    pull_request: GitHubPullRequest | None

    @property
    def needs_rebase(self) -> bool:
        return self.behind_by > 0

    @property
    def recommendation(self) -> str:
        if self.behind_by > 0 and self.ahead_by > 0:
            return f"{self.default_branch} 기준 {self.behind_by}커밋 뒤처짐: rebase 후 push 권장"
        if self.behind_by > 0:
            return f"{self.default_branch} 최신 변경 반영 필요"
        if self.ahead_by > 0:
            return "내 작업만 앞서 있음: PR 생성/갱신 확인"
        return "기본 브랜치와 동일"


class GitHubClient:
    def __init__(self, config: GitHubConfig) -> None:
        self.config = config
        self.headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if config.token:
            self.headers["Authorization"] = f"Bearer {config.token}"

    def find_branches(self, issue_key: str, *, max_per_repo: int = 5) -> list[GitHubBranchMatch]:
        matches: list[GitHubBranchMatch] = []
        needle = issue_key.lower()
        for repo in self.config.repositories:
            for branch in self._branches(repo):
                name = str(branch.get("name", ""))
                if needle not in name.lower():
                    continue
                matches.append(
                    GitHubBranchMatch(
                        repository=f"{repo.owner}/{repo.name}",
                        branch=name,
                        url=f"https://github.com/{repo.owner}/{repo.name}/tree/{quote(name, safe='')}",
                    )
                )
                if len([item for item in matches if item.repository == f"{repo.owner}/{repo.name}"]) >= max_per_repo:
                    break
        return matches

    def current_user(self) -> str:
        payload = json_request("GET", "https://api.github.com/user", headers=self.headers, timeout=30)
        return str(payload.get("login", "")) if isinstance(payload, dict) else ""

    def commits_since(self, since_iso: str, *, author: str = "", max_per_repo: int = 30) -> list[GitHubCommit]:
        items: list[GitHubCommit] = []
        for repo in self.config.repositories:
            query = {"since": since_iso, "per_page": str(max_per_repo)}
            if author:
                query["author"] = author
            url = f"https://api.github.com/repos/{repo.owner}/{repo.name}/commits?{urlencode(query)}"
            payload = json_request("GET", url, headers=self.headers, timeout=30)
            if not isinstance(payload, list):
                continue
            for item in payload[:max_per_repo]:
                commit = item.get("commit", {}) or {}
                commit_author = commit.get("author", {}) or {}
                message = str(commit.get("message", "")).splitlines()[0]
                sha = str(item.get("sha", ""))
                items.append(
                    GitHubCommit(
                        repository=f"{repo.owner}/{repo.name}",
                        sha=sha[:7],
                        message=message,
                        author=str(commit_author.get("name", "")),
                        date=str(commit_author.get("date", "")),
                        url=str(item.get("html_url", "")),
                    )
                )
        return sorted(items, key=lambda item: item.date, reverse=True)

    def active_branches(self, since_iso: str, *, author: str = "", max_per_repo: int = 30) -> list[GitHubBranchActivity]:
        items: list[GitHubBranchActivity] = []
        for repo in self.config.repositories:
            for branch in self._branches(repo)[:max_per_repo]:
                commit_url = str((branch.get("commit", {}) or {}).get("url", ""))
                if not commit_url:
                    continue
                payload = json_request("GET", commit_url, headers=self.headers, timeout=30)
                if not isinstance(payload, dict):
                    continue
                author_login = str((payload.get("author", {}) or {}).get("login", ""))
                if author and author_login and author_login != author:
                    continue
                commit = payload.get("commit", {}) or {}
                commit_author = commit.get("author", {}) or {}
                date = str(commit_author.get("date", ""))
                if date < since_iso:
                    continue
                sha = str(payload.get("sha", ""))
                message = str(commit.get("message", "")).splitlines()[0]
                name = str(branch.get("name", ""))
                items.append(
                    GitHubBranchActivity(
                        repository=f"{repo.owner}/{repo.name}",
                        branch=name,
                        sha=sha[:7],
                        message=message,
                        author=str(commit_author.get("name", "")),
                        date=date,
                        url=f"https://github.com/{repo.owner}/{repo.name}/tree/{quote(name, safe='')}",
                    )
                )
        return sorted(items, key=lambda item: item.date, reverse=True)

    def branch_statuses(self, *, author: str = "", max_per_repo: int = 50) -> list[GitHubBranchStatus]:
        items: list[GitHubBranchStatus] = []
        prs = self.open_pull_requests(max_per_repo=max_per_repo)
        pr_by_branch = {(pr.repository, pr.head_branch): pr for pr in prs}
        for repo in self.config.repositories:
            repo_name = f"{repo.owner}/{repo.name}"
            info = self._repository(repo)
            default_branch = str(info.get("default_branch", "main"))
            for branch in self._branches(repo)[:max_per_repo]:
                name = str(branch.get("name", ""))
                if not name or name == default_branch:
                    continue
                commit_url = str((branch.get("commit", {}) or {}).get("url", ""))
                if not commit_url:
                    continue
                commit_payload = json_request("GET", commit_url, headers=self.headers, timeout=30)
                if not isinstance(commit_payload, dict):
                    continue
                author_login = str((commit_payload.get("author", {}) or {}).get("login", ""))
                pr = pr_by_branch.get((repo_name, name))
                owned_by_author = author_login == author or (pr is not None and pr.author == author)
                if author and not owned_by_author:
                    continue

                comparison = self._compare(repo, default_branch, name)
                commit = commit_payload.get("commit", {}) or {}
                commit_author = commit.get("author", {}) or {}
                sha = str(commit_payload.get("sha", ""))
                message = str(commit.get("message", "")).splitlines()[0]
                items.append(
                    GitHubBranchStatus(
                        repository=repo_name,
                        default_branch=default_branch,
                        branch=name,
                        sha=sha[:7],
                        message=message,
                        author=str(commit_author.get("name", "")),
                        author_login=author_login,
                        date=str(commit_author.get("date", "")),
                        url=f"https://github.com/{repo.owner}/{repo.name}/tree/{quote(name, safe='')}",
                        ahead_by=int(comparison.get("ahead_by", 0)),
                        behind_by=int(comparison.get("behind_by", 0)),
                        status=str(comparison.get("status", "")),
                        pull_request=pr,
                    )
                )
        return sorted(items, key=lambda item: (item.needs_rebase, item.date), reverse=True)

    def _repository(self, repo: GitHubRepository) -> dict:
        url = f"https://api.github.com/repos/{repo.owner}/{repo.name}"
        payload = json_request("GET", url, headers=self.headers, timeout=30)
        return payload if isinstance(payload, dict) else {}

    def _compare(self, repo: GitHubRepository, base: str, head: str) -> dict:
        base_ref = quote(base, safe="")
        head_ref = quote(head, safe="")
        url = f"https://api.github.com/repos/{repo.owner}/{repo.name}/compare/{base_ref}...{head_ref}"
        payload = json_request("GET", url, headers=self.headers, timeout=30)
        return payload if isinstance(payload, dict) else {}

    def _branches(self, repo: GitHubRepository) -> list[dict]:
        url = f"https://api.github.com/repos/{repo.owner}/{repo.name}/branches?per_page=100"
        payload = json_request("GET", url, headers=self.headers, timeout=30)
        return payload if isinstance(payload, list) else []

    def open_pull_requests(self, *, max_per_repo: int = 10) -> list[GitHubPullRequest]:
        items: list[GitHubPullRequest] = []
        for repo in self.config.repositories:
            url = f"https://api.github.com/repos/{repo.owner}/{repo.name}/pulls?state=open&per_page={max_per_repo}"
            payload = json_request("GET", url, headers=self.headers, timeout=30)
            if not isinstance(payload, list):
                continue
            for pr in payload[:max_per_repo]:
                items.append(
                    GitHubPullRequest(
                        repository=f"{repo.owner}/{repo.name}",
                        number=int(pr.get("number", 0)),
                        title=str(pr.get("title", "")),
                        url=str(pr.get("html_url", "")),
                        state=str(pr.get("state", "open")),
                        draft=bool(pr.get("draft", False)),
                        author=str((pr.get("user", {}) or {}).get("login", "")),
                        head_branch=str((pr.get("head", {}) or {}).get("ref", "")),
                        updated_at=str(pr.get("updated_at", "")),
                    )
                )
        return items

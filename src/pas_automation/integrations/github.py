from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote

from pas_automation.config import GitHubConfig, GitHubRepository
from pas_automation.http import json_request


@dataclass(frozen=True)
class GitHubBranchMatch:
    repository: str
    branch: str
    url: str


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

    def _branches(self, repo: GitHubRepository) -> list[dict]:
        url = f"https://api.github.com/repos/{repo.owner}/{repo.name}/branches?per_page=100"
        payload = json_request("GET", url, headers=self.headers, timeout=30)
        return payload if isinstance(payload, list) else []

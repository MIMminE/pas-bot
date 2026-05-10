from __future__ import annotations

from urllib.parse import quote

from pas_automation.config import JiraConfig
from pas_automation.http import basic_auth_header, json_request


class JiraClient:
    def __init__(self, config: JiraConfig) -> None:
        token = config.api_token
        if not token:
            raise RuntimeError("Jira API 토큰이 설정되어 있지 않습니다. config.toml의 [jira].api_token 값을 입력해 주세요.")
        self.config = config
        self.headers = {"Authorization": basic_auth_header(config.email, token)}

    def search(self, jql: str, *, max_results: int = 25) -> list[dict]:
        url = f"{self.config.base_url}/rest/api/3/search/jql"
        payload = json_request(
            "POST",
            url,
            headers=self.headers,
            payload={
                "jql": jql,
                "maxResults": max_results,
                "fields": ["summary", "status", "priority", "assignee", "duedate", "description", "subtasks"],
            },
        )
        return payload.get("issues", [])

    def issue(self, issue_key: str) -> dict:
        url = f"{self.config.base_url}/rest/api/3/issue/{quote(issue_key)}"
        return json_request(
            "GET",
            url,
            headers=self.headers,
            payload=None,
            timeout=30,
        )

    def assign_issue(self, issue_key: str, account_id_or_email: str) -> None:
        account_id = account_id_or_email
        if "@" in account_id_or_email:
            matches = self.find_users(account_id_or_email)
            if not matches:
                raise RuntimeError(f"No Jira user found for {account_id_or_email}")
            account_id = matches[0]["accountId"]

        url = f"{self.config.base_url}/rest/api/3/issue/{quote(issue_key)}/assignee"
        json_request("PUT", url, headers=self.headers, payload={"accountId": account_id})

    def find_users(self, query: str) -> list[dict]:
        url = f"{self.config.base_url}/rest/api/3/user/search?query={quote(query)}&maxResults=5"
        return json_request("GET", url, headers=self.headers)

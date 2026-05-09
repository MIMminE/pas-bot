# PAS 제품 기획서

## 1. 목표

PAS는 Jira, Git, Slack, OpenAI를 연결해 개발자가 매일 반복하는 확인, 정리, 보고 작업을 줄이는 개인 자동화 비서다. 초기 목표는 혼자 안정적으로 쓰는 것이고, 이후 팀 단위로 확장할 수 있게 기능을 작은 단위로 붙인다.

## 2. 1차 기능

- Jira에서 내게 할당된 미처리 일감을 조회해 Slack으로 전송
- Slack 수신 Webhook 테스트 메시지 전송
- 로컬 Git repository snapshot 저장
- snapshot 이후 내 커밋을 모아 일일 작업 보고서 생성
- OpenAI API 키가 있으면 커밋 목록을 한국어 보고서로 요약
- Git repository 상태 요약: 변경 있음, push 필요, pull 확인
- 설정 진단: 필수 설정값과 repository root 확인
- Jira 담당자 alias 파일 import 및 alias 기반 할당
- macOS 메뉴바 앱과 Windows 트레이 앱 제공

## 3. 설정 정책

설정은 OS별 앱 데이터 폴더의 `config.toml` 하나에 저장한다. `.env`는 더 이상 새 배포판에서 생성하지 않는다. 기존 사용자를 위해 CLI의 `--env` 옵션은 당분간 호환용으로 유지한다.

```text
macOS: ~/Library/Application Support/PAS/config.toml
Windows: %APPDATA%\PAS\config.toml
```

Jira 담당자 정보는 같은 폴더의 `assignees.json`에 저장한다. 이 파일은 Jira API의 accountId를 사람이 기억하기 쉬운 alias와 연결한다.

```json
{
  "me": {
    "name": "홍길동",
    "title": "개발자",
    "accountId": "712020:example-account-id"
  }
}
```

주요 설정값:

```toml
[general]
timezone = "Asia/Seoul"
git_author = "your-git-name-or-email"
work_end_time = "18:00"
data_dir = ".pas"

[jira]
base_url = "https://your-company.atlassian.net"
email = "you@example.com"
api_token = ""
default_project = "LMS"
todo_jql = "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC"

[slack]
webhook_url = ""

[openai]
api_key = ""
model = "gpt-5-mini"
```

`config.toml`은 로컬 전용 파일이며 git에 커밋하지 않는다. 릴리즈 zip에도 실제 사용자 설정은 포함하지 않는다.

## 4. 배포 정책

GitHub Actions는 `v*` 태그가 push될 때만 릴리즈를 만든다.

- macOS CLI zip
- macOS 메뉴바 앱 zip
- Windows CLI zip
- Windows 트레이 앱 zip

배포 산출물에는 런타임이 포함되어 사용자가 별도 Python을 설치하지 않아도 된다. macOS 앱은 현재 임시 서명 상태이므로 개인 테스트에서는 Gatekeeper 예외 처리가 필요하다. 일반 사용자 배포 단계에서는 Apple Developer ID 서명과 공증을 붙인다.

## 5. 확장 아이디어

- 월간 Jira/Git 통합 리포트
- Jira 이슈별 관련 커밋 자동 연결
- Slack Block Kit 리포트 템플릿 고도화
- macOS Keychain, Windows Credential Manager 저장 옵션
- 앱 내부 스케줄러와 실행 로그 뷰어
- 팀원에게 간단히 Jira 일감 할당하는 UI
- Jira API에서 팀원 목록을 주기적으로 갱신하는 기능

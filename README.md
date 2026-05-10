# PAS 자동화

PAS는 Jira, Git, Slack, OpenAI를 묶어서 개인 업무 자동화를 실행하는 로컬 앱/CLI입니다. 지금은 혼자 쓰는 개발자 비서에 초점을 맞추고, 나중에 기능을 계속 붙일 수 있도록 작은 기능 단위로 확장합니다.

## 현재 기능

- Jira에서 내게 할당된 미처리 일감을 조회하고 Slack으로 전송
- Jira 일일 브리핑을 Slack 블록 킷 형태의 리포트 메시지로 전송
- 기능별 Slack 채널 라우팅: Slack Bot Token 기반 채널 선택
- Jira 하위 일감과 Jira 키 기반 로컬 브랜치 후보 표시
- Jira 일감 Slack 카드에서 일감과 관리 중인 로컬 repo를 먼저 연결하고, 연결된 repo의 최신 `dev` 계열 브랜치에서 Jira 키 기반 작업 브랜치 시작
- 출근 브리핑: 오늘 Jira 일감, gh CLI로 등록한 Git 상태, 캘린더 연결 상태
- 캘린더 iCal/ICS 연동과 통합 대시보드 표시
- 퇴근 체크: 미커밋/미푸시 상태, 오늘 보고서, Jira 키 누락 점검
- 브랜치명/커밋 메시지/PR 본문 초안 생성
- Jira 이슈 번호 없는 브랜치/커밋 감지
- AI 기반 Git 작업 요약, PR 설명 초안, Jira 이슈 정리, 월간 회고, 장애/버그 원인 정리 초안
- Slack 앱 연결 테스트
- gh CLI로 접근 가능한 GitHub repository 후보 조회
- 설정 화면에서 선택한 GitHub repository를 내려받고 관리 대상으로 등록
- 현재 브랜치, 변경 파일, push/rebase 필요 여부, 오늘 내 커밋을 모아 일일 작업 보고서 생성
- 작업 보고서 생성 시 수동 메모와 `report-agent.md` 작성 규칙을 AI 입력에 함께 반영
- 작업 콘솔에서 rebase/pull 필요, 변경 있음, push 필요 repository 필터
- 작업 콘솔에서 오늘 커밋 보기, push 실행, dirty 상태 경고, 보고서 수정 후 Slack 전송
- 작업 콘솔에서 Git 요약, PR 초안, 장애/버그 원인 초안 등 AI 기능 빠른 실행
- 출근 Git 정비: 관리 repo fetch, 안전한 fast-forward 자동 최신화, 확인 필요 항목 Slack 알림
- 설정 화면에서 GitHub repository clone 위치 지정
- Git repository 상태 요약: 변경 있음, push 필요, rebase/pull 확인
- 설정 진단: Jira/Slack/OpenAI 설정값과 관리 repository 확인
- macOS SwiftUI 메뉴바 앱
- Windows 트레이 앱
- 태그 기반 GitHub Actions 릴리즈 빌드

## 설정 파일

PAS는 로컬 앱 데이터 폴더의 `config.toml` 하나에 설정을 저장합니다. Slack Bot Token, Jira API 토큰, OpenAI API 키도 여기에 들어갑니다.

```bash
cp config.example.toml config.toml
```

주요 설정값:

```toml
[jira]
base_url = "https://your-company.atlassian.net"
email = "you@example.com"
api_token = ""
default_project = "LMS"

[slack]
bot_token = ""

[slack.channels]
default = ""
test = ""
morning_briefing = ""
evening_check = ""
jira_daily = ""
git_report = ""
git_status = ""
alerts = ""

[openai]
api_key = ""
model = "gpt-5-mini"

[developer]
default_ide_app = ""
clone_root = "/Users/yourname/STL"

[calendar]
enabled = false
lookahead_days = 1

[[calendar.sources]]
name = "work"
url = ""
path = ""

[feature_groups]
jira = true
git = true
routines = true
ai = true
dev_tools = true
notifications = true

[schedules.morning_briefing]
enabled = false
time = "09:00"
catch_up_if_missed = true
weekdays_only = true
holiday_dates = []

# 설정 화면에서 GitHub 후보를 가져오면 관리 repository가 자동으로 추가됩니다.
# [[repositories.projects]]
# path = "/Users/yourname/STL/example-service"
```

Slack 전송은 `[slack].bot_token`과 `[slack.channels]`의 채널 ID로 Slack Web API `chat.postMessage`를 사용합니다. macOS 설정 화면에서는 Bot Token 입력 후 채널 목록을 불러와 기능별 채널을 선택할 수 있습니다.
Slack App의 Bot Token Scopes에 `chat:write`, `channels:read`, 비공개 채널까지 쓸 경우 `groups:read`를 추가하고 워크스페이스에 설치해야 합니다.
`[feature_groups]`에서 Jira/Git/루틴/AI/개발 도구/알림 묶음을 끄면 해당 묶음의 수동 실행과 자동 실행 대상에서 제외됩니다. `[schedules.*]`는 OS 스케줄러 등록 여부와 실행 시간을 제어합니다.

## 연결 안내

macOS 설정 화면은 각 외부 서비스의 토큰 생성 페이지를 바로 열 수 있는 접이식 도움말을 제공합니다.

- Slack: Slack App 관리 페이지를 열고 `chat:write`, `channels:read`, 필요 시 `groups:read` 권한을 확인합니다.
- Jira: Atlassian API 토큰 생성 페이지를 열고, 생성한 토큰을 Jira API Token 입력칸에 붙여넣습니다.
- Git: gh CLI 로그인 상태로 GitHub repository 후보를 조회하고, 선택한 repository를 clone 위치에 내려받아 관리 대상으로 등록합니다.

## Jira-Git 작업 원칙

PAS의 기본 업무 흐름은 `Jira 일감 -> 연결 repository -> Jira 키 작업 브랜치 -> PR -> merge`입니다.

- 작업 브랜치 이름에는 `LMS-123` 같은 Jira 키가 포함되어야 합니다.
- `main`, `master`, `dev`, `develop`, `development` 브랜치는 기준 브랜치로 보고 직접 push를 제한합니다.
- Jira 일감 카드의 repository 연결/브랜치 시작 흐름이나 `pas dev start-issue` 명령으로 작업 브랜치를 만든 뒤 개발합니다.
- 관리 repository 상태/퇴근 체크에서는 기준 브랜치 작업과 Jira 키 없는 브랜치를 확인 필요 항목으로 표시합니다.

`config.toml`은 git에 커밋하지 않습니다. 릴리즈 앱을 실행하면 OS별 앱 데이터 폴더에 설정 파일을 만들고, macOS 메뉴바 앱은 시작할 때마다 설정 화면을 먼저 엽니다. 기존 로컬 설정이 있으면 입력값을 미리 채운 상태로 보여주며, 이후 업데이트에서도 같은 로컬 설정을 계속 사용합니다.

Jira 담당자 alias는 같은 폴더의 `assignees.json`에 저장합니다. 이 파일이 있으면 `me`, `choi` 같은 짧은 이름으로 Jira 담당자를 조회하거나 할당할 수 있습니다.

```json
{
  "me": {
    "name": "홍길동",
    "title": "개발자",
    "accountId": "712020:example-account-id"
  }
}
```

```text
macOS: ~/Library/Application Support/PAS/
Windows: %APPDATA%\PAS\
```

생성되는 파일/폴더:

```text
config.toml
assignees.json
report-agent.md
state.json
logs/
snapshots/
```

`state.json`에는 하루 1회 자동 실행 이력과 Jira 일감별 연결 repository가 저장됩니다. 예를 들어 `LMS-310`을 `lms-back`에 연결하면 다음 Jira 브리핑부터 해당 일감 카드에 연결 repo가 표시되고, 브랜치 시작 액션도 그 repo를 기준으로 동작합니다. 브랜치 시작은 처리되지 않은 로컬 변경이 없을 때만 실행되며, `fetch` 후 `dev`, `develop`, `development`, `main`, `master` 순서로 기준 브랜치를 찾아 최신화한 뒤 `feature/LMS-310-summary` 형태의 브랜치를 만듭니다.

`report-agent.md`는 보고서 작성 에이전트 규칙 파일입니다. 앱의 작업 대시보드나 메뉴바의 `보고서 작성 규칙 편집` 화면에서 직접 수정할 수 있고, 오늘 작업 보고서 생성 시 Git 근거와 수동 메모를 이 규칙에 맞춰 AI가 다시 정리합니다.

## CLI

Windows PowerShell:

```powershell
.\scripts\run-pas.ps1 status doctor
.\scripts\run-pas.ps1 status health --no-network
.\scripts\run-pas.ps1 status health --send-alert
.\scripts\run-pas.ps1 slack test
.\scripts\run-pas.ps1 slack test --destination jira_daily
.\scripts\run-pas.ps1 slack channels
.\scripts\run-pas.ps1 jira today --send-slack
.\scripts\run-pas.ps1 repo status --send-slack
.\scripts\run-pas.ps1 repo snapshot --name morning
.\scripts\run-pas.ps1 repo report --snapshot morning --send-slack
.\scripts\run-pas.ps1 repo report --snapshot morning --notes "오늘 PDA 적치 캐시 설계 검토" --report-agent-file "$env:APPDATA\PAS\report-agent.md" --dry-run
.\scripts\run-pas.ps1 jira repo-links
.\scripts\run-pas.ps1 jira link-repo LMS-123 --repo C:\Users\harun\Desktop\STL\lms-back --summary "PDA 입하 캐시 개선"
.\scripts\run-pas.ps1 routine morning --send-slack
.\scripts\run-pas.ps1 routine evening --send-slack
.\scripts\run-pas.ps1 dev branch-name LMS-123 "PDA 입하 캐시 개선"
.\scripts\run-pas.ps1 dev create-branch --repo C:\Users\harun\Desktop\STL\lms-back --issue-key LMS-123 --summary "PDA 입하 캐시 개선" --base-branch dev
.\scripts\run-pas.ps1 dev commit-message --issue-key LMS-123
.\scripts\run-pas.ps1 dev pr-draft --issue-key LMS-123
.\scripts\run-pas.ps1 dev audit-jira-keys
.\scripts\run-pas.ps1 dev dashboard
.\scripts\run-pas.ps1 dev calendar
.\scripts\run-pas.ps1 ai git-summary --tone brief
.\scripts\run-pas.ps1 ai pr-draft --issue-key LMS-123 --tone detailed
.\scripts\run-pas.ps1 ai jira-summary LMS-123 --tone brief
.\scripts\run-pas.ps1 ai monthly-review --month 2026-05 --tone manager
.\scripts\run-pas.ps1 ai incident-draft --issue-key LMS-123 --notes "장애 메모" --tone detailed
.\scripts\run-pas.ps1 automation tick --dry-run
.\scripts\run-pas.ps1 schedule status
.\scripts\run-pas.ps1 schedule install
.\scripts\run-pas.ps1 schedule uninstall
.\scripts\run-pas.ps1 settings import --assignees-file C:\Users\harun\Downloads\assignees.json
.\scripts\run-pas.ps1 settings assignees list
```

macOS:

```bash
scripts/run-pas.sh status doctor
scripts/run-pas.sh status health --no-network
scripts/run-pas.sh status health --send-alert
scripts/run-pas.sh slack test
scripts/run-pas.sh slack test --destination jira_daily
scripts/run-pas.sh slack channels
scripts/run-pas.sh jira today --send-slack
scripts/run-pas.sh repo status --send-slack
scripts/run-pas.sh repo snapshot --name morning
scripts/run-pas.sh repo report --snapshot morning --send-slack
scripts/run-pas.sh repo report --snapshot morning --notes "오늘 PDA 적치 캐시 설계 검토" --report-agent-file "$HOME/Library/Application Support/PAS/report-agent.md" --dry-run
scripts/run-pas.sh jira repo-links
scripts/run-pas.sh jira link-repo LMS-123 --repo ~/Desktop/STL/lms-back --summary "PDA 입하 캐시 개선"
scripts/run-pas.sh routine morning --send-slack
scripts/run-pas.sh routine evening --send-slack
scripts/run-pas.sh dev branch-name LMS-123 "PDA 입하 캐시 개선"
scripts/run-pas.sh dev create-branch --repo ~/Desktop/STL/lms-back --issue-key LMS-123 --summary "PDA 입하 캐시 개선" --base-branch dev
scripts/run-pas.sh dev commit-message --issue-key LMS-123
scripts/run-pas.sh dev pr-draft --issue-key LMS-123
scripts/run-pas.sh dev audit-jira-keys
scripts/run-pas.sh dev dashboard
scripts/run-pas.sh dev calendar
scripts/run-pas.sh ai git-summary --tone brief
scripts/run-pas.sh ai pr-draft --issue-key LMS-123 --tone detailed
scripts/run-pas.sh ai jira-summary LMS-123 --tone brief
scripts/run-pas.sh ai monthly-review --month 2026-05 --tone manager
scripts/run-pas.sh ai incident-draft --issue-key LMS-123 --notes "장애 메모" --tone detailed
scripts/run-pas.sh automation tick --dry-run
scripts/run-pas.sh schedule status
scripts/run-pas.sh schedule install
scripts/run-pas.sh schedule uninstall
scripts/run-pas.sh settings import --assignees-file ~/Downloads/assignees.json
scripts/run-pas.sh settings assignees list
```

## 개발 작업

로컬 개발 task는 `just`를 사용합니다.

macOS:

```bash
brew install just
```

Windows:

```powershell
winget install Casey.Just
```

자주 쓰는 명령:

```bash
just
just check
just smoke
just setup
just install-dev
just package-local
```

## 앱 메뉴

macOS 메뉴바 앱과 Windows 트레이 앱에서 바로 실행할 수 있는 항목:

- Slack 테스트 전송
- Jira 브리핑 전송
- Jira 브리핑 미리보기
- Git 상태 전송
- Git 상태 미리보기
- 설정 진단 실행
- config.toml 가져오기
- 담당자 파일 가져오기
- 담당자 목록 보기
- 설정 열기 또는 설정 폴더 열기
- 마지막 실행 결과 보기
- 마지막 실행 결과 복사

macOS 앱은 실행 시 설정 화면을 열고 Slack Bot Token과 기능별 채널, Jira URL/email/API token/project, Git 작성자, GitHub repository clone 위치, OpenAI API key, 기능별 자동 실행 여부와 시간을 받습니다. macOS와 Windows 모두 앱 메뉴에서 기존 `config.toml` 또는 `assignees.json`을 가져올 수 있습니다.
Jira 테스트, 설정 진단, 미리보기, 가져오기에서 문제가 생기면 별도 결과 창에 상세 오류가 표시됩니다.

스케줄러 등록은 덮어쓰기 방식입니다. 같은 PAS 작업이 이미 OS 스케줄러에 있으면 삭제한 뒤 현재 설정으로 다시 등록합니다. 자동 실행은 `state.json`의 마지막 전송일을 확인해서 같은 날 중복 전송을 막습니다.

## 릴리즈

`v*` 태그를 push하면 GitHub Actions가 OS별 실행 파일이 포함된 zip을 만들고 GitHub 릴리즈에 업로드합니다.

예상 산출물:

- `pas-macos-menubar-arm64.zip`

릴리즈 만들기:

```bash
git tag v0.1.0
git push origin v0.1.0
```

릴리즈 zip에는 Python 런타임이 포함된 `bin/pas` 또는 `bin/pas.exe`가 들어가므로 사용자는 별도로 Python을 설치하지 않아도 됩니다.

현재 macOS 앱은 Apple Developer ID 공증이 없는 임시 서명 빌드입니다. 개인 테스트에서는 Finder에서 우클릭 후 열기를 사용하거나, 필요한 경우 quarantine 속성을 제거해서 실행할 수 있습니다. 일반 사용자에게 자연스럽게 배포하려면 Apple Developer Program과 공증을 붙이는 것이 좋습니다.

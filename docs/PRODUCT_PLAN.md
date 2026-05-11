# PAS 제품 기획서

## 1. 목표

PAS는 Jira, Git, Slack, OpenAI를 연결해 개발자가 매일 반복하는 확인, 정리, 보고 작업을 줄이는 개인 자동화 비서다. 초기 목표는 혼자 안정적으로 쓰는 것이고, 이후 팀 단위로 확장할 수 있게 기능을 작은 단위로 붙인다.

## 2. 1차 기능

- Jira에서 내게 할당된 미처리 일감을 조회해 Slack으로 전송
- Slack Bot Token 기반 테스트 메시지 전송
- 관리 Git repository snapshot 저장
- gh CLI로 접근 가능한 GitHub repository 후보를 조회하고, 설정 화면에서 선택한 관리 대상만 현재 브랜치, rebase/pull 필요 여부, 오늘 내 커밋 기준으로 일일 작업 보고서에 사용
- 작업 콘솔은 rebase/pull 필요, 변경 있음, push 필요 repository 필터와 오늘 커밋 보기, push 실행, dirty 상태 경고를 제공한다.
- 작업 콘솔은 보고서 미리보기, 수정 후 Slack 전송, Git 요약/PR 초안/장애 원인 초안 같은 AI 기능 빠른 실행을 제공한다.
- 작업 콘솔은 사용자가 직접 적은 수동 메모와 `report-agent.md` 보고서 작성 규칙을 AI 보고서 생성에 함께 반영한다.
- 출근 Git 정비는 관리 repo 전체 fetch 후 안전한 fast-forward만 자동 처리하고, 확인 필요/실패/최신 상태를 Slack으로 전체 알림한다.
- 관리 Git repository의 브랜치/커밋/변경 상태 기반 작업 리포트 생성
- 설정 화면에서 GitHub repository clone 위치 지정
- OpenAI API 키가 있으면 커밋 목록을 한국어 보고서로 요약
- AI 확장 명령: Git 요약, PR 설명 초안, Jira 이슈 정리, 월간 회고, 장애/버그 원인 정리
- Git repository 상태 요약: 변경 있음, push 필요, rebase/pull 확인
- 설정 진단: 필수 설정값과 관리 repository 확인
- Jira 담당자 alias 파일 import 및 alias 기반 할당
- Jira 이슈의 하위 일감과 Jira 키 기반 로컬 브랜치 후보 표시
- Jira 일감 Slack 카드에서 일감과 관리 중인 로컬 repo를 연결하고, 연결된 repo의 최신 `dev` 계열 브랜치에서 Jira 키 기반 작업 브랜치를 생성
- 기능별 Slack 채널 라우팅: Jira, Git 보고서, Git 상태, 테스트, 긴급 알림을 서로 다른 채널로 전송
- Slack 앱 연결 모드: Bot Token으로 채널 목록을 조회하고 기능별 채널을 선택해 `chat.postMessage`로 전송
- iCal/ICS 기반 캘린더 일정 조회와 출근 브리핑/통합 대시보드 연계
- macOS 메뉴바 앱 제공

## 3. 설정 정책

설정은 macOS 앱 데이터 폴더의 `config.toml` 하나에 저장한다. `.env`는 더 이상 새 배포판에서 생성하지 않는다. 기존 사용자를 위해 CLI의 `--env` 옵션은 당분간 호환용으로 유지한다.

```text
macOS: ~/Library/Application Support/PAS/config.toml
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

[schedules.jira_daily]
enabled = false
time = "09:00"
catch_up_if_missed = true

[schedules.git_report]
enabled = false
time = "18:30"
catch_up_if_missed = true

[schedules.git_status]
enabled = false
time = "09:10"
catch_up_if_missed = true

[[repositories.roots]]
path = "/Users/yourname/STL"
recursive = false

[[repositories.projects]]
path = "/Users/yourname/STL/example-service"
base_branch = "dev"
```

Slack 전송은 `[slack].bot_token`과 `[slack.channels]`의 기능별 채널 ID를 사용한다. macOS 설정 화면은 Bot Token으로 채널 목록을 조회하고, 사용자가 기능별 채널을 선택할 수 있게 한다.
필요한 Slack Bot Token Scope는 `chat:write`, `channels:read`, 비공개 채널 사용 시 `groups:read`다.

설정 화면은 토큰 입력 부담을 줄이기 위해 각 서비스의 공식 생성/안내 페이지를 접이식 도움말에서 직접 열 수 있게 한다.

- Slack: Slack App 관리와 scope 안내 페이지로 이동
- Jira: Atlassian API token 생성 페이지와 공식 안내 문서로 이동
- Git: gh CLI로 접근 가능한 repository 후보를 조회하고 선택한 repository를 clone 위치에 내려받아 등록

기능별 Slack 채널:

- `test`: Slack 연결 테스트
- `morning_briefing`: 출근 브리핑
- `evening_check`: 퇴근 체크
- `jira_daily`: Jira 오늘 일감 브리핑
- `git_report`: 관리 repository 상태와 오늘 내 커밋 기반 일일 보고서
- `git_status`: 관리 repository 변경/push/pull 상태 점검
- `alerts`: 이후 긴급 알림, 실패 알림, 장기 미처리 알림

`config.toml`은 로컬 전용 파일이며 git에 커밋하지 않는다. 릴리즈 zip에도 실제 사용자 설정은 포함하지 않는다.

스케줄 정책:

- `[feature_groups]`로 Jira/Git/루틴/AI/개발 도구/알림 묶음의 활성 여부를 제어한다.
- `[schedules.*].enabled`는 각 자동 실행 항목의 등록 여부만 제어한다.
- OS 스케줄러 등록은 덮어쓰기 방식으로 동작한다. 같은 PAS 작업이 있으면 제거 후 재등록한다.
- 스케줄러는 `pas automation tick --task ...`만 실행하고, 실제 하루 1회 전송 여부는 PAS가 `state.json`으로 판단한다.
- 설정 시간이 지났고 오늘 전송 이력이 없으면 실행한다. 컴퓨터가 꺼져 있어서 놓친 경우에도 `RunAtLoad` 또는 로그인 이후 tick 실행 시 한 번 보낸다.
- 비활성화된 작업은 등록 시 기존 스케줄만 제거하고 새로 등록하지 않는다.

Jira 일감과 관리 repository 연결:

- 연결 정보는 `state.json`의 `issue_repositories`에 저장한다.
- Slack Jira 브리핑에서 아직 연결되지 않은 일감은 `레포 연결 선택` 액션을 제공한다.
- macOS 앱은 딥링크를 받아 관리 중인 repository 목록을 보여주고, 사용자가 선택한 repo를 해당 Jira 키에 연결한다.
- 이미 연결된 일감은 브리핑 카드와 작업 콘솔에서 연결 repo를 표시하고, 브랜치 시작/커밋 수집/PR 초안 같은 후속 기능의 기본 컨텍스트로 사용한다.
- 브랜치 시작은 로컬 변경이 없는 경우에만 실행한다. `fetch` 후 `dev`, `develop`, `development`, `main`, `master` 순서로 기준 브랜치를 찾고 fast-forward 가능한 최신 상태에서 `feature/LMS-123-summary` 형식의 작업 브랜치를 생성한다.
- 각 관리 repository는 `base_branch`를 기준 브랜치로 저장한다. 현재 체크아웃 브랜치가 기준 브랜치와 다르면 작업중으로 표시하고, 기준 브랜치보다 뒤처진 작업 브랜치는 rebase 필요 상태로 보여준다.

보고서 작성 에이전트:

- 앱 데이터 폴더에 `report-agent.md`를 둔다.
- 파일은 AGENTS.md처럼 보고서 작성 규칙, 섹션, 말투, 금지사항을 담는다.
- macOS 앱은 작업 대시보드와 메뉴바에서 보고서 작성 규칙 편집 UI를 제공한다.
- 일일 Git 보고서 생성 시 Git 근거, repository 상태, 수동 메모, `report-agent.md`를 함께 AI에 전달한다.
- OpenAI API 키가 없으면 AI 정리는 건너뛰고 Git 근거와 수동 메모를 합친 초안을 표시한다.

AI 확장 정책:

- OpenAI API 키가 없으면 원본 데이터 기반 fallback 초안을 제공한다.
- `--tone brief|detailed|manager` 옵션으로 보고 톤을 선택한다.
- AI 결과는 초안으로 취급하며, Jira/장애 원인처럼 사실성이 중요한 문서는 확인된 사실과 추정 사항을 구분한다.
- 지원 명령: `ai git-summary`, `ai pr-draft`, `ai jira-summary`, `ai monthly-review`, `ai incident-draft`.

## 4. 배포 정책

GitHub Actions는 `v*` 태그가 push될 때만 릴리즈를 만든다.

- macOS CLI zip
- macOS 메뉴바 앱 zip
배포 산출물에는 런타임이 포함되어 사용자가 별도 Python을 설치하지 않아도 된다. macOS 앱은 현재 임시 서명 상태이므로 개인 테스트에서는 Gatekeeper 예외 처리가 필요하다. 일반 사용자 배포 단계에서는 Apple Developer ID 서명과 공증을 붙인다.

## 5. 확장 아이디어

- 월간 Jira/Git 통합 리포트
- Jira 이슈별 관련 커밋 자동 연결
- 로컬 브랜치에서 Jira 키와 일치하는 작업 후보 표시 및 Slack 버튼 기반 브랜치 생성
- 기존 git 인증을 이용한 `git fetch`/원격 추적 브랜치 점검 고도화
- 일감별 개발 힌트: 관련 브랜치, 최근 커밋, 하위 일감 진행 상태, 막힌 기간을 하나의 카드로 정리
- 여러 Slack 채널 운영: 개인 DM, 팀 공유 채널, Git 보고 채널, 실패 알림 채널 분리
- Slack Block Kit 리포트 템플릿 고도화
- macOS Keychain 저장 옵션
- 앱 내부 스케줄러와 실행 로그 뷰어
- 팀원에게 간단히 Jira 일감 할당하는 UI
- Jira API에서 팀원 목록을 주기적으로 갱신하는 기능

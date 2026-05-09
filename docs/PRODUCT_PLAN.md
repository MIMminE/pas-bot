# PAS 기획서

## 1. 개요

PAS는 Slack Incoming Webhook을 중심으로 동작하는 개인화 업무 자동화 비서 애플리케이션이다. 사용자가 정의한 업무 데이터 소스(Jira, Git repository, 추후 캘린더/메일/문서 등)를 주기적으로 확인하고, 필요한 내용을 정리하거나 알림 형태로 Slack 지정 채널에 전송한다.

초기 목표는 다음 두 가지 기능을 안정적으로 제공하는 것이다.

- Jira에서 내게 할당된 미처리 일감을 읽고 매일 지정한 시간에 Slack으로 브리핑한다.
- 내가 참여하는 Git repository들을 기준으로 오늘 내가 작업한 commit을 모아 OpenAI API로 간단한 일일 업무 보고서를 생성하고 Slack으로 전송한다.

장기적으로는 단순 알림 도구가 아니라, 사용자의 업무 흐름을 대신 관찰하고 정리해주는 개인 업무 운영 시스템으로 확장한다.

## 2. 핵심 사용 시나리오

### 2.1 아침 Jira 브리핑

매일 아침 지정된 시간에 Jira API를 호출하여 내게 할당된 미처리 일감을 가져온다. 결과는 Slack 채널에 다음 형태로 전송한다.

```text
오늘의 Jira 일감 - 2026-05-09
오늘의 Jira 일감: 미처리 3개, 어제 할당 2개, 5일 이상 0개, 높은 우선순위 2개

내게 할당된 미처리 일감

LMS-310 [어제 할당] [높은 우선순위] PDA 입하 후 적치 처리시 LOT 입력 캐시 저장 필요
상태: Backlog | 우선순위: Highest | 마감: -
내용: ...
```

이 기능은 OpenAI API 없이도 동작할 수 있어야 한다. 즉, 비용 없이 단순 조회/정리만으로 기본 브리핑을 제공한다.

### 2.2 Git 기반 퇴근 보고서

출근 또는 지정 시각에 사용자가 참여하는 repository들의 snapshot을 저장한다. 퇴근 또는 지정 시각에는 snapshot 이후 현재까지의 commit 중 사용자의 git author와 일치하는 commit을 수집한다.

수집된 commit 목록은 OpenAI API에 전달하여 Slack에 올리기 적합한 짧은 한국어 업무 보고서로 정리한다.

예상 출력:

```text
오늘 한 일

- PDA 입하 적치 과정에서 LOT 입력 캐시 유지 흐름을 개선했습니다.
- 신규입고 적치 화면에서 로케이션 현황을 확인할 수 있도록 관련 처리 구조를 정리했습니다.
- 재고 조정 업로드 후 수량 반영 이슈를 확인하고 수정 범위를 분석했습니다.

참고
- LMS-310, LMS-232 관련 작업을 중심으로 진행했습니다.
```

이 기능은 OpenAI API 사용 여부를 설정으로 제어할 수 있어야 한다. API key가 없거나 비활성화된 경우에는 commit 목록 기반의 fallback 보고서를 생성한다.

## 3. 범위

### 3.1 1차 제공 범위

- Slack Incoming Webhook 전송
- Jira 오늘 일감 브리핑
- Git repository snapshot
- Git commit 기반 일일 보고서 생성
- OpenAI API 기반 보고서 정리
- macOS `launchd` 자동 실행
- Windows 개발/테스트 실행
- 설정 파일과 비밀 환경변수 분리

### 3.2 추후 확장 후보

- Slack 메시지 예약/DM 전송
- Jira 이슈 생성/할당/상태 변경
- GitHub/GitLab PR 리뷰 요약
- 캘린더 기반 하루 일정 브리핑
- 메일/문서/회의록 요약
- 작업 시간 추적
- macOS 메뉴바 앱
- Windows 트레이 앱 또는 위젯
- 간단한 로컬 대시보드 UI
- ChatGPT/MCP 연동을 통한 대화형 명령

## 4. 시스템 구조

초기 구조는 CLI 기반 자동화로 시작한다.

```text
Scheduler
  - macOS launchd
  - Windows Task Scheduler

PAS CLI
  - config loader
  - Jira feature
  - Git report feature
  - Slack sender
  - OpenAI report writer

External Services
  - Jira REST API
  - Slack Incoming Webhook
  - OpenAI API
  - Local Git repositories
```

초기에는 서버를 상시 실행하지 않고, 정해진 시간에 CLI가 실행되고 종료되는 구조로 운영한다. 이 방식은 단순하고 장애 범위가 작으며, 개인 자동화 용도에 적합하다.

메뉴바 앱이나 트레이 앱을 추가할 때는 내부적으로 같은 CLI 또는 Python package를 호출하도록 구성한다. 즉, 핵심 업무 로직은 UI와 분리한다.

## 5. 설정 전략

설정은 두 계층으로 분리한다.

### 5.1 `config.toml`

비밀이 아닌 설정을 저장한다. repository에 예시 파일(`config.example.toml`)을 포함할 수 있다.

```toml
[general]
timezone = "Asia/Seoul"
git_author = "your-git-name-or-email"
work_end_time = "18:00"
data_dir = ".pas"

[jira]
base_url = "https://your-company.atlassian.net"
email = "you@example.com"
token_env = "JIRA_API_TOKEN"
default_project = "LMS"
todo_jql = "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC"
yesterday_assigned_jql = "assignee = currentUser() AND assignee CHANGED TO currentUser() DURING (startOfDay(-1), startOfDay())"
stale_jql = "assignee = currentUser() AND statusCategory != Done AND updated <= -5d"
high_priority_jql = "assignee = currentUser() AND statusCategory != Done AND priority in (Highest, High)"

[slack]
webhook_url_env = "SLACK_WEBHOOK_URL"

[openai]
api_key_env = "OPENAI_API_KEY"
model = "gpt-5-mini"

[[repositories.roots]]
path = "/Users/yourname/STL"
recursive = true
```

### 5.2 `.env`

비밀값을 저장한다. 이 파일은 git에 올리지 않는다.

```bash
JIRA_BASE_URL=
JIRA_EMAIL=
JIRA_API_TOKEN=
JIRA_DEFAULT_PROJECT=
SLACK_WEBHOOK_URL=
OPENAI_API_KEY=
```

`.env`는 로컬 실행 스크립트에서만 읽는다. 애플리케이션 코드는 환경변수 이름을 통해 비밀값을 참조한다.

## 6. 환경변수 정의

| 이름 | 필수 여부 | 용도 | 비밀 여부 | 비고 |
|---|---:|---|---:|---|
| `JIRA_BASE_URL` | 선택 | Jira base URL | 아니오 | 현재는 `config.toml` 값 우선 사용. 추후 env override 가능 |
| `JIRA_EMAIL` | 선택 | Jira 계정 이메일 | 부분적 | 현재는 `config.toml` 값 우선 사용 |
| `JIRA_API_TOKEN` | 필수 | Jira REST API 인증 토큰 | 예 | 절대 git에 커밋하지 않음 |
| `JIRA_DEFAULT_PROJECT` | 선택 | 기본 Jira 프로젝트 키 | 아니오 | 예: `LMS` |
| `SLACK_WEBHOOK_URL` | 필수 | Slack Incoming Webhook URL | 예 | URL 자체가 비밀값 |
| `OPENAI_API_KEY` | 선택 | OpenAI API 호출용 key | 예 | AI 보고서 기능 사용 시 필요 |
| `PYTHON_BIN` | 선택 | macOS 실행 스크립트에서 사용할 Python 경로 | 아니오 | 기본값 `python3` |
| `PYTHONPATH` | 실행 시 설정 | 로컬 source package 경로 | 아니오 | scripts에서 자동 설정 |

## 7. 보안 원칙

- `.env`는 git에 올리지 않는다.
- Slack webhook URL은 password처럼 취급한다.
- Jira API token과 OpenAI API key는 문서, README, issue, Slack에 그대로 노출하지 않는다.
- 배포 zip에 실제 `.env`를 포함할지 여부는 상황별로 결정한다.
  - 개인 장비 간 이동용 zip: 포함 가능
  - GitHub 업로드/공유용 zip: 절대 포함하지 않음
- 로그에는 token, webhook URL, API key를 출력하지 않는다.
- Slack 전송 전 dry-run 모드를 제공하여 메시지 내용을 확인할 수 있게 한다.

## 8. OpenAI API 사용 방침

OpenAI API는 모든 기능에 기본으로 사용하지 않는다. 규칙 기반 포맷팅으로 충분한 기능은 코드에서 처리한다.

OpenAI API 사용이 적합한 경우:

- commit 목록을 사람이 읽기 좋은 업무 보고서로 묶기
- Jira 설명을 간결한 요약으로 바꾸기
- 여러 데이터 소스를 합쳐 우선순위/리스크를 정리하기
- 보고서 문체를 Slack에 맞게 다듬기

OpenAI API를 사용하지 않아도 되는 경우:

- 단순 Jira 목록 조회
- 개수 집계
- 상태/우선순위 badge 표시
- 정해진 템플릿 메시지 전송

비용 관리를 위해 다음 원칙을 둔다.

- Jira description은 길이 제한을 둔다.
- commit diff 전체를 보내지 않고 commit message 중심으로 시작한다.
- 필요 시 파일명/변경량 정도만 추가한다.
- 모델명은 설정에서 교체 가능하게 한다.
- API key가 없을 때 fallback 보고서를 생성한다.

## 9. Windows/macOS 운영 전략

### 9.1 Windows

Windows는 개발 및 테스트 환경으로 사용한다.

- PowerShell에서 CLI 직접 실행
- 기능 개발 및 압축 패키지 생성
- 추후 Windows Task Scheduler 등록 지원
- 추후 tray app 또는 desktop widget 검토

### 9.2 macOS

macOS는 1차 실제 운영 환경으로 사용한다.

- `launchd`로 매일 지정 시간 실행
- `scripts/*.sh`로 `.env` 로드 후 CLI 실행
- 추후 메뉴바 앱 추가

macOS 초기 명령:

```bash
cd ~/PAS
chmod +x scripts/*.sh
scripts/check-local-setup.sh
scripts/test-slack-now.sh
scripts/test-jira-slack-now.sh
scripts/install-jira-daily-launchd.sh
```

## 10. UI 확장 방향

### 10.1 macOS 메뉴바 앱

추후 macOS에서는 카카오톡처럼 상단 메뉴바에 아이콘을 두고 다음 기능을 제공한다.

- 다음 실행 시간 확인
- 지금 Jira 브리핑 보내기
- 지금 Slack 테스트 보내기
- 최근 실행 로그 보기
- 자동 실행 켜기/끄기
- 설정 파일 열기

초기 구현 후보:

- Python + rumps
- SwiftUI 메뉴바 앱
- Tauri 기반 cross-platform shell

### 10.2 Windows 트레이/위젯

Windows에서는 시스템 트레이 앱 또는 작은 dashboard를 고려한다.

- 지금 실행
- 최근 로그 확인
- 스케줄 상태 확인
- 설정 파일 열기

초기에는 CLI와 스케줄러를 우선 안정화하고, UI는 핵심 기능이 굳어진 뒤 붙인다.

## 11. Git 보관 전략

추후 개인 Git 계정으로 repository를 만든다.

커밋 가능:

- source code
- README
- docs
- `config.example.toml`
- `.env.example`
- launchd/script template

커밋 금지:

- `.env`
- `config.toml`
- `.pas/`
- log files
- token이 포함된 zip

권장 `.gitignore`:

```gitignore
__pycache__/
*.py[cod]
.pas/
.env
config.toml
.venv/
*.zip
```

## 12. 1차 구현 체크리스트

- [x] 기본 Python CLI 구조
- [x] Slack Incoming Webhook 전송
- [x] Jira 오늘 일감 브리핑
- [x] Jira 브리핑 즉시 테스트 스크립트
- [x] macOS launchd 등록 스크립트
- [x] 공통 CLI wrapper 스크립트
- [x] `.env` 기반 환경변수 로딩
- [x] 태그 기반 GitHub Actions 릴리즈 워크플로
- [x] PyInstaller 기반 Python 런타임 포함 배포 구조
- [ ] Jira API 실제 mac 환경 테스트
- [ ] Slack 실제 전송 확인
- [ ] OpenAI API key 설정 방식 확정
- [ ] Git commit 보고서 실제 repository 기준 테스트
- [ ] Windows Task Scheduler 지원 여부 결정
- [ ] GitHub 개인 repository 생성

## 13. 다음 단계 제안

1. macOS에서 Jira-Slack 브리핑 실제 전송을 확인한다.
2. launchd 등록 후 재부팅/재로그인 이후에도 실행되는지 확인한다.
3. Git commit 보고서 기능을 macOS의 실제 STL 경로 기준으로 테스트한다.
4. OpenAI API key를 `.env`에 추가하고 퇴근 보고서 문체를 다듬는다.
5. 설정값을 UI에서 관리할지, 계속 파일 기반으로 둘지 결정한다.
6. 개인 Git repository에 secret 제외 상태로 최초 커밋한다.

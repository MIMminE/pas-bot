# PAS 자동화

PAS는 Jira, Git, Slack, OpenAI를 묶어서 개인 업무 자동화를 실행하는 로컬 앱/CLI입니다. 지금은 혼자 쓰는 개발자 비서에 초점을 맞추고, 나중에 기능을 계속 붙일 수 있도록 작은 기능 단위로 확장합니다.

## 현재 기능

- Jira에서 내게 할당된 미처리 일감을 조회하고 Slack으로 전송
- Jira 일일 브리핑을 Slack 블록 킷 형태의 리포트 메시지로 전송
- Slack 수신 Webhook 연결 테스트
- 로컬 Git repository snapshot 저장
- snapshot 이후 내 커밋을 모아 OpenAI 기반 일일 작업 보고서 생성
- Git repository 상태 요약: 변경 있음, push 필요, pull 확인
- 설정 진단: Jira/Slack/OpenAI 환경변수와 repository root 확인
- macOS SwiftUI 메뉴바 앱
- Windows 트레이 앱
- 태그 기반 GitHub Actions 릴리즈 빌드

## 설정 파일

비밀이 아닌 설정은 `config.toml`에 둡니다.

```bash
cp config.example.toml config.toml
```

비밀 값은 `.env`에 둡니다.

```bash
cp .env.example .env
```

주요 환경변수:

```bash
JIRA_BASE_URL=
JIRA_EMAIL=
JIRA_API_TOKEN=
JIRA_DEFAULT_PROJECT=
SLACK_WEBHOOK_URL=
OPENAI_API_KEY=
```

`.env`와 `config.toml`은 git에 커밋하지 않습니다.

릴리즈 앱을 처음 실행하면 OS별 앱 데이터 폴더에 초기 파일을 생성하고, 이후 업데이트에서는 기존 로컬 설정을 계속 사용합니다.

```text
macOS: ~/Library/Application Support/PAS/
Windows: %APPDATA%\PAS\
```

생성되는 파일/폴더:

```text
config.toml
.env
state.json
logs/
snapshots/
```

## CLI

Windows PowerShell:

```powershell
.\scripts\run-pas.ps1 status doctor
.\scripts\run-pas.ps1 slack test
.\scripts\run-pas.ps1 jira today --send-slack
.\scripts\run-pas.ps1 repo status --send-slack
.\scripts\run-pas.ps1 repo snapshot --name morning
.\scripts\run-pas.ps1 repo report --snapshot morning --send-slack
```

macOS:

```bash
scripts/run-pas.sh status doctor
scripts/run-pas.sh slack test
scripts/run-pas.sh jira today --send-slack
scripts/run-pas.sh repo status --send-slack
scripts/run-pas.sh repo snapshot --name morning
scripts/run-pas.sh repo report --snapshot morning --send-slack
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

macOS 메뉴바 앱과 Windows tray 앱에서 바로 실행할 수 있는 항목:

- Slack 테스트 전송
- Jira 브리핑 전송
- Jira 브리핑 미리보기
- Git 상태 전송
- Git 상태 미리보기
- 설정 진단 실행
- 초기 설정 열기 또는 설정 폴더 열기
- 마지막 실행 결과 복사

macOS 앱은 첫 실행 시 초기 설정 창을 열고 Slack webhook, Jira URL/email/token/project를 받습니다. Windows는 현재 트레이 메뉴와 설정 폴더 열기를 우선 제공합니다.

## 릴리즈

`v*` 태그를 push하면 GitHub Actions가 OS별 실행 파일이 포함된 zip을 만들고 GitHub 릴리즈에 업로드합니다.

예상 산출물:

- `pas-windows-x64.zip`
- `pas-macos-arm64.zip`
- `pas-macos-menubar-arm64.zip`
- `pas-windows-tray-x64.zip`

릴리즈 만들기:

```bash
git tag v0.1.0
git push origin v0.1.0
```

릴리즈 zip에는 Python 런타임이 포함된 `bin/pas` 또는 `bin/pas.exe`가 들어가므로 사용자는 별도로 Python을 설치하지 않아도 됩니다.

현재 macOS 앱은 Apple Developer ID 공증이 없는 임시 서명 빌드입니다. 개인 테스트에서는 Finder에서 우클릭 후 열기를 사용하거나, 필요한 경우 quarantine 속성을 제거해서 실행할 수 있습니다. 일반 사용자에게 자연스럽게 배포하려면 Apple Developer Program과 공증을 붙이는 것이 좋습니다.

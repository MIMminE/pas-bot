# PAS Automation

PAS는 Slack Incoming Webhook을 중심으로 동작하는 개인 업무 자동화 CLI입니다. Jira 브리핑, Git 커밋 기반 일일 보고서, OpenAI 요약, Slack 전송을 작은 기능 단위로 확장해 갑니다.

## 현재 기능

- Jira에서 내게 할당된 미처리 일감을 조회해 Slack으로 전송
- Slack webhook 테스트 메시지 전송
- 로컬 Git repository snapshot 저장
- snapshot 이후 내 commit을 모아 OpenAI 기반 일일 보고서 생성
- macOS `launchd` 자동 실행 스크립트
- macOS SwiftUI 메뉴바 앱 골격
- Windows 트레이 앱 골격
- 태그 기반 GitHub Actions 릴리즈 빌드

## 설정 파일

비밀이 아닌 설정은 `config.toml`에 둡니다.

```bash
cp config.example.toml config.toml
```

비밀값은 `.env`에 둡니다.

```bash
cp .env.example .env
```

필수/주요 환경변수:

```bash
JIRA_BASE_URL=
JIRA_EMAIL=
JIRA_API_TOKEN=
JIRA_DEFAULT_PROJECT=
SLACK_WEBHOOK_URL=
OPENAI_API_KEY=
```

`.env`와 `config.toml`은 git에 커밋하지 않습니다.

릴리즈 앱은 최초 실행 시 OS별 앱 데이터 폴더에 초기 파일을 생성하고, 이후부터는 그 로컬 데이터를 계속 사용합니다.

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

앱 업데이트 시 기존 로컬 설정은 덮어쓰지 않습니다.

## 개발 환경 실행

Gradle task처럼 로컬 개발 작업을 실행할 수 있도록 `just`를 사용합니다.

설치:

```bash
brew install just
```

Windows:

```powershell
winget install Casey.Just
```

```bash
just
just check
just smoke
```

Windows에서도 같은 명령을 사용합니다.

```powershell
just
just check
just smoke
```

로컬 가상환경 생성:

```bash
just setup
```

로컬에서 PyInstaller 패키징까지 테스트하려면 dev dependency를 설치합니다.

```bash
just install-dev
just package-local
```

릴리즈 산출물은 GitHub Actions에서 만들기 때문에 로컬 패키징은 검증용입니다.

```bash
chmod +x scripts/*.sh
scripts/run-pas.sh slack test --dry-run
scripts/run-pas.sh jira today --dry-run
```

Windows PowerShell:

```powershell
.\scripts\run-pas.ps1 slack test --dry-run
.\scripts\run-pas.ps1 jira today --dry-run
```

## macOS 즉시 테스트

```bash
scripts/check-local-setup.sh
scripts/test-slack-now.sh
scripts/test-jira-slack-now.sh
```

## macOS 자동 실행

Jira 아침 브리핑만 등록:

```bash
scripts/install-jira-daily-launchd.sh
launchctl start com.pas.jira-daily
```

해제:

```bash
scripts/uninstall-jira-daily-launchd.sh
```

기본 시간은 매일 09:00이며, `launchd/com.pas.jira-daily.plist`의 `Hour`, `Minute` 값으로 변경합니다.

## 릴리즈

태그를 푸시하면 GitHub Actions가 OS별 실행 파일을 포함한 zip을 생성하고 GitHub Release에 업로드합니다.

생성 예정 산출물:

- `pas-windows-x64.zip`
- `pas-macos-arm64.zip`
- `pas-macos-menubar-arm64.zip`
- `pas-windows-tray-x64.zip`

릴리즈 만들기:

```bash
git tag v0.1.0
git push origin v0.1.0
```

릴리즈 zip에는 Python 런타임이 포함된 `bin/pas` 또는 `bin/pas.exe`가 들어갑니다. 사용자는 별도로 Python을 설치하지 않아도 됩니다.

`pas-macos-menubar-arm64.zip`에는 `PAS.app`이 들어갑니다. 앱은 내부에 포함된 `bin/pas`를 호출하며, 설정 파일은 최초 실행 시 `~/Library/Application Support/PAS/` 아래에 예시 파일로 생성됩니다.
처음 실행하면 Setup 창이 열리고 Slack webhook, Jira URL/email/token/project를 입력한 뒤 바로 Slack 테스트와 Jira dry-run을 실행할 수 있습니다.

현재 macOS 앱은 Apple Developer ID notarization이 없는 ad-hoc signed 빌드입니다. 처음 실행 시 Gatekeeper가 막으면 Finder에서 우클릭 후 `Open`을 사용하거나, 시스템 설정의 보안 허용을 사용해야 할 수 있습니다.

`pas-windows-tray-x64.zip`에는 `PASTray.exe`가 들어갑니다. 앱은 내부에 포함된 `bin/pas.exe`를 호출하며, 설정 파일은 최초 실행 시 `%APPDATA%\PAS\` 아래에 예시 파일로 생성됩니다.

릴리즈 zip을 푼 뒤:

```bash
cp config.example.toml config.toml
cp .env.example .env
scripts/run-pas.sh slack test
```

Windows:

```powershell
Copy-Item config.example.toml config.toml
Copy-Item .env.example .env
.\scripts\run-pas.ps1 slack test
```

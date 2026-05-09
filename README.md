# PAS Automation

개인 업무 자동화를 위한 Python CLI입니다. 실제 운영은 macOS에 설치해 두고 `launchd`로 정해진 시간마다 실행하는 구성을 기준으로 합니다.

## 기능

- Jira 오늘 일감 브리핑을 Slack 채널로 전송
- Jira 이슈를 나 또는 팀원에게 간단히 할당
- 로컬 STL 하위 git repo의 아침 스냅샷 저장
- 퇴근 시간 기준 내 git 커밋을 모아 OpenAI로 일일 보고서 작성
- 작성된 보고서를 Slack Incoming Webhook으로 전송

## macOS 설치

```bash
cd ~/PAS
cp config.example.toml config.toml
cp .env.example .env
chmod +x scripts/*.sh
```

`config.toml`에서 아래 값을 실제 환경에 맞게 수정합니다.

- `general.git_author`: `git config --global user.name` 또는 email
- `jira.base_url`: 회사 Jira URL
- `jira.email`: Jira 계정 email
- `repositories.roots.path`: STL repo들이 들어있는 macOS 경로

`.env`에는 토큰 값을 넣습니다. 이 파일은 git에 올리지 않습니다.

```bash
JIRA_API_TOKEN=...
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
OPENAI_API_KEY=...
```

## 수동 테스트

mac으로 옮긴 직후에는 아래 순서로 확인합니다.

```bash
cd ~/PAS
chmod +x scripts/*.sh
scripts/check-local-setup.sh
scripts/test-slack-now.sh
scripts/test-jira-slack-now.sh
```

각 스크립트 역할:

- `scripts/check-local-setup.sh`: `config.toml`, `.env`, `python3`, 필수 환경변수 확인
- `scripts/test-slack-now.sh`: Slack 테스트 메시지를 실제 채널로 전송
- `scripts/test-jira-slack-now.sh`: Jira 오늘 일감을 조회해서 Slack으로 즉시 전송

```bash
scripts/run-pas.sh slack test
scripts/run-pas.sh jira today --dry-run
scripts/run-pas.sh jira today --send-slack
```

repo 보고서 흐름:

```bash
scripts/run-pas.sh repo snapshot --name morning
scripts/run-pas.sh repo report --snapshot morning --dry-run
scripts/run-pas.sh repo report --snapshot morning --send-slack
```

Slack Incoming Webhook URL은 생성할 때 선택한 채널에 고정됩니다. 다른 채널로 보내려면 Slack 앱 설정에서 해당 채널용 webhook을 하나 더 만들고 `.env`의 `SLACK_WEBHOOK_URL` 값을 바꿉니다.

## launchd 등록

Jira 아침 브리핑만 먼저 켜려면 아래만 실행하면 됩니다.

```bash
chmod +x scripts/*.sh
scripts/install-jira-daily-launchd.sh
launchctl start com.pas.jira-daily
```

이렇게 등록하면 mac에 다시 로그인해도 매일 09:00에 Jira 일감 브리핑이 Slack으로 전송됩니다.

Jira 브리핑만 끄기:

```bash
scripts/uninstall-jira-daily-launchd.sh
```

repo 스냅샷과 퇴근 보고까지 모두 켜려면 아래 전체 등록 절차를 사용합니다.

템플릿의 `/Users/yourname/PAS`를 실제 설치 경로로 바꿉니다.

```bash
sed "s#/Users/yourname/PAS#$HOME/PAS#g" launchd/com.pas.jira-daily.plist > ~/Library/LaunchAgents/com.pas.jira-daily.plist
sed "s#/Users/yourname/PAS#$HOME/PAS#g" launchd/com.pas.repo-snapshot.plist > ~/Library/LaunchAgents/com.pas.repo-snapshot.plist
sed "s#/Users/yourname/PAS#$HOME/PAS#g" launchd/com.pas.repo-report.plist > ~/Library/LaunchAgents/com.pas.repo-report.plist
mkdir -p .pas/logs
launchctl load ~/Library/LaunchAgents/com.pas.jira-daily.plist
launchctl load ~/Library/LaunchAgents/com.pas.repo-snapshot.plist
launchctl load ~/Library/LaunchAgents/com.pas.repo-report.plist
```

기본 실행 시간:

- `com.pas.jira-daily`: 매일 09:00 Jira 일감 Slack 브리핑
- `com.pas.repo-snapshot`: 매일 09:05 repo 스냅샷
- `com.pas.repo-report`: 매일 18:00 repo 기반 일일 보고서 Slack 전송

즉시 실행 테스트:

```bash
launchctl start com.pas.jira-daily
launchctl start com.pas.repo-snapshot
launchctl start com.pas.repo-report
```

등록 해제:

```bash
launchctl unload ~/Library/LaunchAgents/com.pas.jira-daily.plist
launchctl unload ~/Library/LaunchAgents/com.pas.repo-snapshot.plist
launchctl unload ~/Library/LaunchAgents/com.pas.repo-report.plist
```

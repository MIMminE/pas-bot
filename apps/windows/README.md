# PAS Windows Tray

Windows UI는 `apps/windows/PASTray` 아래의 WinForms 트레이 앱으로 관리합니다.

앱은 업무 로직을 직접 구현하지 않고, 릴리즈 패키지에 함께 포함되는 `bin/pas.exe`를 호출합니다.

초기 기능:

- Slack 테스트 전송
- Jira 브리핑 전송
- Jira 브리핑 dry-run
- 설정 폴더 열기
- 최근 결과 복사
- 종료

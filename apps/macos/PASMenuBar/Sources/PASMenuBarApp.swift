import SwiftUI

@main
struct PASMenuBarApp: App {
    @StateObject private var runner = PASRunner()

    var body: some Scene {
        MenuBarExtra("PAS", systemImage: runner.isRunning ? "bolt.circle.fill" : "bolt.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text(runner.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Divider()

                Button("Slack 테스트 전송") {
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning)

                Button("Jira 브리핑 전송") {
                    runner.run(["jira", "today", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Button("Jira 브리핑 미리보기") {
                    runner.run(["jira", "today", "--dry-run"])
                }
                .disabled(runner.isRunning)

                Divider()

                Button("Git 상태 전송") {
                    runner.run(["repo", "status", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Button("Git 상태 미리보기") {
                    runner.run(["repo", "status", "--dry-run"])
                }
                .disabled(runner.isRunning)

                Button("출근 Git 정비 전송") {
                    runner.run(["repo", "morning-sync", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Button("Git 작업 보고 스냅샷 저장") {
                    runner.run(["repo", "snapshot", "--name", "morning"])
                }
                .disabled(runner.isRunning)

                Button("Git 작업 보고 전송") {
                    runner.run(["repo", "report", "--snapshot", "morning", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Button("Git 작업 보고 미리보기") {
                    runner.run(["repo", "report", "--snapshot", "morning", "--dry-run"])
                }
                .disabled(runner.isRunning)

                Button("설정 진단 실행") {
                    runner.run(["status", "doctor"])
                }
                .disabled(runner.isRunning)

                Divider()

                Button("config.toml 가져오기") {
                    runner.importConfigFile()
                }
                .disabled(runner.isRunning)

                Button("담당자 파일 가져오기") {
                    runner.importAssigneesFile()
                }
                .disabled(runner.isRunning)

                Button("담당자 목록 보기") {
                    runner.run(["settings", "assignees", "list"])
                }
                .disabled(runner.isRunning)

                Divider()

                Button("작업 콘솔 열기") {
                    runner.openWorkWindow()
                }

                Button("설정 열기") {
                    runner.openSetupWindow()
                }

                Button("설정 폴더 열기") {
                    runner.openSupportDirectory()
                }

                Button("마지막 실행 결과 보기") {
                    runner.openLastOutputWindow()
                }
                .disabled(runner.lastOutput.isEmpty)

                Button("마지막 실행 결과 복사") {
                    runner.copyLastOutput()
                }
                .disabled(runner.lastOutput.isEmpty)

                Divider()

                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 260)
        }
        .menuBarExtraStyle(.menu)
    }
}

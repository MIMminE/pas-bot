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

                Button("설정 진단 실행") {
                    runner.run(["status", "doctor"])
                }
                .disabled(runner.isRunning)

                Divider()

                Button("초기 설정 열기") {
                    runner.openSetupWindow()
                }

                Button("설정 폴더 열기") {
                    runner.openSupportDirectory()
                }

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
            .frame(width: 240)
        }
        .menuBarExtraStyle(.menu)
    }
}

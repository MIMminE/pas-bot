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

                Button("Send Slack Test") {
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning)

                Button("Send Jira Briefing") {
                    runner.run(["jira", "today", "--send-slack"])
                }
                .disabled(runner.isRunning)

                Button("Jira Briefing Dry Run") {
                    runner.run(["jira", "today", "--dry-run"])
                }
                .disabled(runner.isRunning)

                Divider()

                Button("Open Settings Folder") {
                    runner.openSupportDirectory()
                }

                Button("Copy Last Output") {
                    runner.copyLastOutput()
                }
                .disabled(runner.lastOutput.isEmpty)

                Divider()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 240)
        }
        .menuBarExtraStyle(.menu)
    }
}

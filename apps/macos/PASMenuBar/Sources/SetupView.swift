import SwiftUI

struct SetupView: View {
    @ObservedObject var runner: PASRunner

    @State private var settings: PASSettings

    init(runner: PASRunner) {
        self.runner = runner
        _settings = State(initialValue: runner.loadSettings())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PAS 초기 설정")
                .font(.title2)
                .bold()

            Text("Jira 일감과 Slack 알림을 테스트하기 위한 최소 설정을 입력하세요.")
                .foregroundStyle(.secondary)

            GroupBox("Slack") {
                VStack(alignment: .leading) {
                    Text("수신 Webhook URL")
                    TextField("https://hooks.slack.com/services/...", text: $settings.slackWebhookURL)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Jira") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("기본 URL")
                        TextField("https://start-today.atlassian.net", text: $settings.jiraBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("이메일")
                        TextField("you@example.com", text: $settings.jiraEmail)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("API Token")
                        SecureField("Jira API 토큰", text: $settings.jiraApiToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("기본 프로젝트")
                        TextField("LMS", text: $settings.jiraDefaultProject)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button("설정 폴더 열기") {
                    runner.openSupportDirectory()
                }

                Spacer()

                Button("저장") {
                    runner.saveSettings(settings)
                }
                .keyboardShortcut(.defaultAction)

                Button("저장 후 닫기") {
                    runner.saveSettings(settings)
                    runner.closeSetupWindow()
                }
                .disabled(!settings.isReadyForBasicTests)
            }

            Divider()

            HStack {
                Button("Slack 테스트 전송") {
                    runner.saveSettings(settings)
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning || !settings.slackWebhookURL.hasPrefix("https://hooks.slack.com/services/"))

                Button("Jira 미리보기") {
                    runner.saveSettings(settings)
                    runner.run(["jira", "today", "--dry-run"])
                }
                .disabled(runner.isRunning || !settings.isReadyForBasicTests)

                Spacer()

                Text(runner.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

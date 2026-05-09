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
            Text("PAS Setup")
                .font(.title2)
                .bold()

            Text("Enter the minimum settings required to send Jira updates to Slack.")
                .foregroundStyle(.secondary)

            GroupBox("Slack") {
                VStack(alignment: .leading) {
                    Text("Incoming Webhook URL")
                    TextField("https://hooks.slack.com/services/...", text: $settings.slackWebhookURL)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Jira") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Base URL")
                        TextField("https://start-today.atlassian.net", text: $settings.jiraBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Email")
                        TextField("you@example.com", text: $settings.jiraEmail)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("API Token")
                        SecureField("Jira API token", text: $settings.jiraApiToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Project")
                        TextField("LMS", text: $settings.jiraDefaultProject)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button("Open Settings Folder") {
                    runner.openSupportDirectory()
                }

                Spacer()

                Button("Save") {
                    runner.saveSettings(settings)
                }
                .keyboardShortcut(.defaultAction)

                Button("Save & Close") {
                    runner.saveSettings(settings)
                    runner.closeSetupWindow()
                }
                .disabled(!settings.isReadyForBasicTests)
            }

            Divider()

            HStack {
                Button("Send Slack Test") {
                    runner.saveSettings(settings)
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning || !settings.slackWebhookURL.hasPrefix("https://hooks.slack.com/services/"))

                Button("Jira Dry Run") {
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

import SwiftUI

struct SetupView: View {
    @ObservedObject var runner: PASRunner

    @State private var settings: PASSettings
    @State private var slackChannels: [SlackChannel] = []

    init(runner: PASRunner) {
        self.runner = runner
        _settings = State(initialValue: runner.loadSettings())
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    slackSection
                    jiraSection
                    developerSection
                    automationSection
                    testSection
                }
                .padding(20)
            }

            footer
        }
        .frame(minWidth: 720, minHeight: 660)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PAS 설정 마법사")
                    .font(.title2)
                    .bold()

                Text("Jira, Slack, GitHub, Git 작업 보고를 개인 개발 비서 흐름에 맞게 연결합니다.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusPill: some View {
        Text(runner.status)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var slackSection: some View {
        GroupBox("Slack 목적지") {
            VStack(alignment: .leading, spacing: 10) {
                Text("웹훅 직접 입력 또는 Slack 앱 연결 방식으로 기능별 전송 채널을 지정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("연결 방식", selection: $settings.slackMode) {
                    Text("Webhook 직접 입력").tag("webhook")
                    Text("Slack 앱 연결").tag("oauth")
                }
                .pickerStyle(.segmented)

                if settings.usesSlackOAuth {
                    SettingsSecureField(title: "Bot Token", placeholder: "xoxb-...", text: $settings.slackBotToken)

                    GuideBox(
                        title: "Slack 앱 연결 안내",
                        lines: [
                            "Slack App을 만들고 Bot Token Scopes에 chat:write, channels:read를 추가합니다.",
                            "비공개 채널까지 선택하려면 groups:read도 추가한 뒤 앱을 워크스페이스에 설치합니다.",
                            "설치 후 Bot User OAuth Token 값을 여기에 입력하면 채널 목록을 불러올 수 있습니다."
                        ],
                        buttons: [
                            GuideButton(title: "Slack 앱 관리 열기", url: "https://api.slack.com/apps"),
                            GuideButton(title: "chat:write 권한 보기", url: "https://api.slack.com/scopes/chat%3Awrite")
                        ],
                        runner: runner
                    )

                    HStack {
                        Button("채널 목록 불러오기") {
                            slackChannels = runner.loadSlackChannels(settings: settings)
                        }
                        .disabled(runner.isRunning || settings.slackBotToken.isEmpty)

                        Text("Slack App 권한: chat:write, channels:read, groups:read")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    if slackChannels.isEmpty {
                        ChannelIdField(title: "기본", text: $settings.slackDefaultChannelID)
                        ChannelIdField(title: "연결 테스트", text: $settings.slackTestChannelID)
                        ChannelIdField(title: "출근 브리핑", text: $settings.slackMorningChannelID)
                        ChannelIdField(title: "퇴근 체크", text: $settings.slackEveningChannelID)
                        ChannelIdField(title: "Jira 아침 브리핑", text: $settings.slackJiraChannelID)
                        ChannelIdField(title: "Git 오늘 한 일 보고", text: $settings.slackGitReportChannelID)
                        ChannelIdField(title: "Git 상태 점검", text: $settings.slackGitStatusChannelID)
                        ChannelIdField(title: "긴급 알림", text: $settings.slackAlertsChannelID)
                    } else {
                        ChannelPicker(title: "기본", channels: slackChannels, selection: $settings.slackDefaultChannelID)
                        ChannelPicker(title: "연결 테스트", channels: slackChannels, selection: $settings.slackTestChannelID)
                        ChannelPicker(title: "출근 브리핑", channels: slackChannels, selection: $settings.slackMorningChannelID)
                        ChannelPicker(title: "퇴근 체크", channels: slackChannels, selection: $settings.slackEveningChannelID)
                        ChannelPicker(title: "Jira 아침 브리핑", channels: slackChannels, selection: $settings.slackJiraChannelID)
                        ChannelPicker(title: "Git 오늘 한 일 보고", channels: slackChannels, selection: $settings.slackGitReportChannelID)
                        ChannelPicker(title: "Git 상태 점검", channels: slackChannels, selection: $settings.slackGitStatusChannelID)
                        ChannelPicker(title: "긴급 알림", channels: slackChannels, selection: $settings.slackAlertsChannelID)
                    }
                } else {
                    WebhookField(title: "기본", text: $settings.slackDefaultWebhookURL)
                    WebhookField(title: "연결 테스트", text: $settings.slackTestWebhookURL)
                    WebhookField(title: "Jira 아침 브리핑", text: $settings.slackJiraWebhookURL)
                    WebhookField(title: "Git 오늘 한 일 보고", text: $settings.slackGitReportWebhookURL)
                    WebhookField(title: "Git 상태 점검", text: $settings.slackGitStatusWebhookURL)
                    WebhookField(title: "긴급 알림", text: $settings.slackAlertsWebhookURL)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var jiraSection: some View {
        GroupBox("Jira") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsTextField(title: "기본 URL", placeholder: "https://start-today.atlassian.net", text: $settings.jiraBaseURL)
                SettingsTextField(title: "이메일", placeholder: "you@example.com", text: $settings.jiraEmail)
                SettingsSecureField(title: "API Token", placeholder: "Jira API 토큰", text: $settings.jiraApiToken)
                SettingsTextField(title: "기본 프로젝트", placeholder: "LMS", text: $settings.jiraDefaultProject)

                GuideBox(
                    title: "Jira API 토큰 안내",
                    lines: [
                        "Jira Cloud는 계정 이메일과 API 토큰으로 REST API를 호출합니다.",
                        "토큰을 만든 뒤 API Token 입력칸에 붙여넣고, 기본 프로젝트에는 LMS 같은 프로젝트 키를 입력합니다.",
                        "토큰은 다시 볼 수 없으니 저장 후 분실하면 새로 만들어야 합니다."
                    ],
                    buttons: [
                        GuideButton(title: "Atlassian 토큰 만들기", url: "https://id.atlassian.com/manage-profile/security/api-tokens"),
                        GuideButton(title: "공식 안내 보기", url: "https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/")
                    ],
                    runner: runner
                )
            }
            .padding(.vertical, 6)
        }
    }

    private var developerSection: some View {
        GroupBox("개발자 비서 확장") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsTextField(title: "Git 작성자", placeholder: "git user.name 또는 email", text: $settings.gitAuthor)
                SettingsTextField(title: "퇴근 기준 시간", placeholder: "18:00", text: $settings.workEndTime)
                SettingsSecureField(title: "GitHub Token", placeholder: "GitHub fine-grained token", text: $settings.githubToken)
                SettingsSecureField(title: "OpenAI API Key", placeholder: "Git 보고서 AI 요약 사용 시 입력", text: $settings.openAIKey)

                Text("GitHub 저장소 목록과 로컬 repository root는 설정 폴더의 config.toml에서 계속 확장할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GuideBox(
                    title: "GitHub 토큰 안내",
                    lines: [
                        "private repository, PR, 브랜치 조회에는 GitHub 토큰이 필요합니다.",
                        "fine-grained token을 만들고 PAS가 볼 repository를 선택합니다.",
                        "현재 기능은 repository contents/metadata 읽기와 PR 조회 권한을 중심으로 사용합니다."
                    ],
                    buttons: [
                        GuideButton(title: "GitHub 토큰 만들기", url: "https://github.com/settings/personal-access-tokens/new"),
                        GuideButton(title: "공식 안내 보기", url: "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens")
                    ],
                    runner: runner
                )
            }
            .padding(.vertical, 6)
        }
    }

    private var testSection: some View {
        GroupBox("검증") {
            HStack(spacing: 10) {
                Button("Slack 테스트 전송") {
                    runner.saveSettings(settings)
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning || !settings.isReadyForSlackTest)

                Menu("목적지별 테스트") {
                    Button("연결 테스트 채널") { runSlackTest("test") }
                    Button("Jira 브리핑 채널") { runSlackTest("jira_daily") }
                    Button("Git 보고 채널") { runSlackTest("git_report") }
                    Button("Git 상태 채널") { runSlackTest("git_status") }
                    Button("긴급 알림 채널") { runSlackTest("alerts") }
                }
                .disabled(runner.isRunning)

                Button("Jira 미리보기") {
                    runner.saveSettings(settings)
                    runner.run(["jira", "today", "--dry-run"])
                }
                .disabled(runner.isRunning || !settings.isReadyForBasicTests)

                Button("설정 진단") {
                    runner.saveSettings(settings)
                    runner.run(["status", "doctor"])
                }
                .disabled(runner.isRunning)

                Button("스케줄 상태") {
                    runner.saveSettings(settings)
                    runner.run(["schedule", "status"])
                }
                .disabled(runner.isRunning)

                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private var automationSection: some View {
        GroupBox("자동 실행") {
            VStack(alignment: .leading, spacing: 12) {
                Text("기능을 끄면 수동 실행과 자동 실행 대상에서 제외됩니다. 스케줄 등록은 기존 항목을 지우고 현재 설정으로 다시 등록합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScheduleRow(
                    title: "Jira 아침 브리핑",
                    featureEnabled: $settings.jiraDailyEnabled,
                    scheduleEnabled: $settings.jiraDailyScheduleEnabled,
                    time: $settings.jiraDailyScheduleTime,
                    catchUp: $settings.jiraDailyCatchUp,
                    placeholder: "09:00"
                )

                ScheduleRow(
                    title: "Git 오늘 한 일 보고",
                    featureEnabled: $settings.gitReportEnabled,
                    scheduleEnabled: $settings.gitReportScheduleEnabled,
                    time: $settings.gitReportScheduleTime,
                    catchUp: $settings.gitReportCatchUp,
                    placeholder: "18:30"
                )

                ScheduleRow(
                    title: "Git 상태 점검",
                    featureEnabled: $settings.gitStatusEnabled,
                    scheduleEnabled: $settings.gitStatusScheduleEnabled,
                    time: $settings.gitStatusScheduleTime,
                    catchUp: $settings.gitStatusCatchUp,
                    placeholder: "09:10"
                )

                HStack {
                    Button("스케줄러 등록/갱신") {
                        runner.saveSettings(settings)
                        runner.run(["schedule", "install"])
                    }
                    .disabled(runner.isRunning)

                    Button("스케줄러 제거") {
                        runner.run(["schedule", "uninstall"])
                    }
                    .disabled(runner.isRunning)

                    Button("자동 실행 테스트") {
                        runner.saveSettings(settings)
                        runner.run(["automation", "tick", "--dry-run"])
                    }
                    .disabled(runner.isRunning)

                    Spacer()
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var footer: some View {
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
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func runSlackTest(_ destination: String) {
        runner.saveSettings(settings)
        runner.run(["slack", "test", "--destination", destination])
    }
}

private struct SettingsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct SettingsSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct WebhookField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsTextField(
            title: title,
            placeholder: "https://hooks.slack.com/services/...",
            text: $text
        )
    }
}

private struct GuideButton: Hashable {
    let title: String
    let url: String
}

private struct GuideBox: View {
    let title: String
    let lines: [String]
    let buttons: [GuideButton]
    let runner: PASRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .bold()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text("· \(line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                ForEach(buttons, id: \.self) { item in
                    Button(item.title) {
                        runner.openExternalURL(item.url)
                    }
                }
                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChannelIdField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsTextField(
            title: title,
            placeholder: "C0123456789",
            text: $text
        )
    }
}

private struct ChannelPicker: View {
    let title: String
    let channels: [SlackChannel]
    @Binding var selection: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                Picker(title, selection: $selection) {
                    Text("기본 채널 사용").tag("")
                    ForEach(channels) { channel in
                        Text(channel.label).tag(channel.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ScheduleRow: View {
    let title: String
    @Binding var featureEnabled: Bool
    @Binding var scheduleEnabled: Bool
    @Binding var time: String
    @Binding var catchUp: Bool
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $featureEnabled)
                .font(.headline)

            HStack(spacing: 12) {
                Toggle("자동 전송", isOn: $scheduleEnabled)
                    .disabled(!featureEnabled)

                TextField(placeholder, text: $time)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                    .disabled(!featureEnabled || !scheduleEnabled)

                Toggle("놓친 경우 켜진 시점에 1회 전송", isOn: $catchUp)
                    .disabled(!featureEnabled || !scheduleEnabled)

                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

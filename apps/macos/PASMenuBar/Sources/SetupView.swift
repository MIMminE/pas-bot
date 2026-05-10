import SwiftUI

struct SetupView: View {
    @ObservedObject var runner: PASRunner

    @State private var settings: PASSettings
    @State private var slackChannels: [SlackChannel] = []
    @State private var localRepositories: [LocalRepositoryOption] = []
    @State private var remoteRepositories: [GitHubRemoteRepositoryOption] = []
    @State private var selectedRemoteRepositoryIDs: Set<String> = []
    @State private var remoteOwner = ""
    @State private var remoteCloneRoot = ""
    @State private var isLoadingSlackChannels = false
    @State private var isLoadingLocalRepositories = false
    @State private var isLoadingRemoteRepositories = false
    @State private var isCloningRemoteRepositories = false
    @State private var isSlackExpanded = true
    @State private var isJiraExpanded = true
    @State private var isDeveloperExpanded = true
    @State private var isAutomationExpanded = false
    @State private var isTestExpanded = false

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
                Text("PAS 설정")
                    .font(.title2)
                    .bold()

                Text("Jira, Slack, 로컬 Git 작업 보고를 개인 개발 비서 흐름에 맞게 연결합니다.")
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
        SettingsSection(
            title: "Slack 채널 설정",
            summary: "기능별 알림을 보낼 Slack 채널을 연결합니다.",
            systemImage: "number",
            isExpanded: $isSlackExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Slack 앱 Bot Token으로 채널 목록을 불러오고, 기능별 전송 채널을 지정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    Button(isLoadingSlackChannels ? "불러오는 중..." : "채널 목록 불러오기") {
                        isLoadingSlackChannels = true
                        Task {
                            slackChannels = await runner.loadSlackChannels(settings: settings)
                            isLoadingSlackChannels = false
                        }
                    }
                    .disabled(runner.isRunning || settings.slackBotToken.isEmpty || isLoadingSlackChannels)

                    if isLoadingSlackChannels {
                        ProgressView()
                            .controlSize(.small)
                        Text("Slack에서 채널을 확인하는 중")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
            }
            .padding(.vertical, 6)
        }
    }

    private var jiraSection: some View {
        SettingsSection(
            title: "Jira 연결",
            summary: "내게 할당된 일감과 프로젝트 기본값을 읽기 위한 정보를 입력합니다.",
            systemImage: "checklist",
            isExpanded: $isJiraExpanded
        ) {
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
        SettingsSection(
            title: "개발자 비서 확장",
            summary: "gh CLI로 GitHub repository를 가져오고 AI 보고서 옵션을 설정합니다.",
            systemImage: "terminal",
            isExpanded: $isDeveloperExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsTextField(title: "Git 작성자", placeholder: "git user.name 또는 email", text: $settings.gitAuthor)
                SettingsTextField(title: "퇴근 기준 시간", placeholder: "18:00", text: $settings.workEndTime)
                SettingsSecureField(title: "OpenAI API Key", placeholder: "Git 보고서 AI 요약 사용 시 입력", text: $settings.openAIKey)

                Text("GitHub CLI 로그인 상태로 접근 가능한 repository 후보를 조회하고, 선택한 repository를 내려받아 관리 대상으로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GuideBox(
                    title: "GitHub CLI 연결 안내",
                    lines: [
                        "터미널에서 gh auth login을 한 번 진행하면 PAS가 같은 로그인 상태로 repository 후보를 조회합니다.",
                        "조직 repository가 보이지 않으면 GitHub 조직 SSO 승인이 필요할 수 있습니다.",
                        "선택한 repository는 지정한 clone 위치에 내려받고, 이미 있으면 fetch로 원격 상태만 갱신합니다."
                    ],
                    buttons: [
                        GuideButton(title: "GitHub CLI 설치 안내", url: "https://cli.github.com/"),
                        GuideButton(title: "gh auth login 안내", url: "https://cli.github.com/manual/gh_auth_login")
                    ],
                    runner: runner
                )

                remoteRepositorySection

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(isLoadingLocalRepositories ? "불러오는 중..." : "관리 repository 새로고침") {
                            isLoadingLocalRepositories = true
                            Task {
                                localRepositories = await runner.loadLocalRepositories(settings: settings)
                                isLoadingLocalRepositories = false
                            }
                        }
                        .disabled(runner.isRunning || isLoadingLocalRepositories)

                        if isLoadingLocalRepositories {
                            ProgressView()
                                .controlSize(.small)
                            Text("등록된 Git repository 상태를 확인하는 중")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("관리 repository \(settings.repoProjectPaths.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    if localRepositories.isEmpty {
                        Text("아직 관리 repository가 없습니다. 위에서 GitHub 후보를 조회한 뒤 선택 repo를 가져오면 여기에 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LocalRepositoryProjectPicker(
                            repositories: localRepositories,
                            selectedPaths: $settings.repoProjectPaths
                        )
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.vertical, 6)
        }
    }

    private var remoteRepositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GitHub repository 후보")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text("gh CLI 로그인 사용")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("owner 또는 org 예: MIMminE, start-today-stl", text: $remoteOwner)
                    .textFieldStyle(.roundedBorder)

                TextField("/Users/you/STL", text: $remoteCloneRoot)
                    .textFieldStyle(.roundedBorder)

                Button("위치 선택") {
                    runner.selectRepositoryRoot { path in
                        remoteCloneRoot = path
                        if !settings.repoRoots.contains(where: { $0.path == path }) {
                            settings.repoRoots.append(LocalRepositoryRoot(path: path, recursive: false))
                        }
                    }
                }

                Button(isLoadingRemoteRepositories ? "조회 중..." : "후보 불러오기") {
                    Task { await loadRemoteRepositories() }
                }
                .disabled(runner.isRunning || isLoadingRemoteRepositories)
            }

            if isLoadingRemoteRepositories || isCloningRemoteRepositories {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(isCloningRemoteRepositories ? "선택한 repository를 내려받고 동기화하는 중" : "GitHub repository 후보를 조회하는 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if remoteRepositories.isEmpty {
                Text("후보를 불러오면 gh CLI로 접근 가능한 repository 목록이 표시됩니다. 선택한 repository는 clone 위치에 내려받고 관리 대상으로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RemoteRepositoryPicker(
                    repositories: remoteRepositories,
                    selectedIDs: $selectedRemoteRepositoryIDs
                )

                HStack {
                    Button("선택 repo 가져오기/동기화") {
                        Task { await cloneSelectedRemoteRepositories() }
                    }
                    .disabled(
                        runner.isRunning
                            || isCloningRemoteRepositories
                            || selectedRemoteRepositoryIDs.isEmpty
                            || remoteCloneRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text("선택 \(selectedRemoteRepositoryIDs.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var testSection: some View {
        SettingsSection(
            title: "연결 확인",
            summary: "저장한 설정으로 Slack, Jira, 스케줄 상태를 바로 확인합니다.",
            systemImage: "stethoscope",
            isExpanded: $isTestExpanded
        ) {
            HStack(spacing: 10) {
                Button("Slack 테스트 전송") {
                    runner.saveSettings(settings)
                    runner.run(["slack", "test"])
                }
                .disabled(runner.isRunning || !settings.isReadyForSlackTest)

                Menu("채널별 테스트") {
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
        SettingsSection(
            title: "자동 실행",
            summary: "기능별 실행 여부와 하루 한 번 실행할 시간을 정합니다.",
            systemImage: "clock.arrow.circlepath",
            isExpanded: $isAutomationExpanded
        ) {
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

    private func loadRemoteRepositories() async {
        isLoadingRemoteRepositories = true
        if remoteCloneRoot.isEmpty, let firstRoot = settings.repoRoots.first(where: { !$0.path.isEmpty }) {
            remoteCloneRoot = firstRoot.path
        }
        remoteRepositories = await runner.loadRemoteRepositories(owner: remoteOwner)
        selectedRemoteRepositoryIDs.removeAll()
        isLoadingRemoteRepositories = false
    }

    private func cloneSelectedRemoteRepositories() async {
        let targetRoot = remoteCloneRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetRoot.isEmpty else { return }
        let selected = remoteRepositories.filter { selectedRemoteRepositoryIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        isCloningRemoteRepositories = true
        if !settings.repoRoots.contains(where: { $0.path == targetRoot }) {
            settings.repoRoots.append(LocalRepositoryRoot(path: targetRoot, recursive: false))
        }
        for repo in selected {
            let result = await runner.cloneRemoteRepository(repo, targetRoot: targetRoot)
            if result.succeeded {
                let localPath = parseClonedPath(result.displayText)
                if !localPath.isEmpty {
                    settings.repoProjectPaths.insert(localPath)
                }
            }
        }
        runner.saveSettings(settings)
        localRepositories = await runner.loadLocalRepositories(settings: settings)
        selectedRemoteRepositoryIDs.removeAll()
        isCloningRemoteRepositories = false
    }

    private func parseClonedPath(_ output: String) -> String {
        output.split(separator: "\n").first?.split(separator: "\t").first.map(String.init) ?? ""
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

private struct GuideButton: Hashable {
    let title: String
    let url: String
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let summary: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        summary: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
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
                    Text("- \(line)")
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
            .padding(.top, 6)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
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

private struct LocalRepositoryProjectPicker: View {
    let repositories: [LocalRepositoryOption]
    @Binding var selectedPaths: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("관리 repository")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button("전체 선택") {
                    selectedPaths = Set(repositories.map(\.path))
                }

                Button("전체 해제") {
                    selectedPaths.removeAll()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(repositories) { repo in
                    Toggle(isOn: Binding(
                        get: { selectedPaths.contains(repo.path) },
                        set: { isSelected in
                            if isSelected {
                                selectedPaths.insert(repo.path)
                            } else {
                                selectedPaths.remove(repo.path)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(repo.name)
                                    .font(.body)
                                Text(repo.branch)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                if repo.dirtyCount > 0 {
                                    Text("변경 \(repo.dirtyCount)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                            }

                            Text("\(repo.syncLabel) | \(repo.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

private struct RemoteRepositoryPicker: View {
    let repositories: [GitHubRemoteRepositoryOption]
    @Binding var selectedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("가져올 GitHub repository")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button("전체 선택") {
                    selectedIDs = Set(repositories.map(\.id))
                }

                Button("전체 해제") {
                    selectedIDs.removeAll()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(repositories) { repo in
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(repo.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedIDs.insert(repo.id)
                                } else {
                                    selectedIDs.remove(repo.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(repo.nameWithOwner)
                                        .font(.body)
                                    Text(repo.visibility)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    if !repo.defaultBranch.isEmpty {
                                        Text(repo.defaultBranch)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                Text(repo.sshURL.isEmpty ? repo.webURL : repo.sshURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
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
